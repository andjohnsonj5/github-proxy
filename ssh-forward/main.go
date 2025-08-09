package main

import (
    "context"
    "errors"
    "flag"
    "io"
    "log"
    "net"
    "os"
    "os/signal"
    "runtime"
    "strconv"
    "strings"
    "sync"
    "syscall"
    "time"
)

// envDefault returns env var value or fallback.
func envDefault(key, def string) string {
    if v := strings.TrimSpace(os.Getenv(key)); v != "" {
        return v
    }
    return def
}

func parseDurationEnv(key string, def time.Duration) time.Duration {
    if v := strings.TrimSpace(os.Getenv(key)); v != "" {
        d, err := time.ParseDuration(v)
        if err == nil {
            return d
        }
    }
    return def
}

type config struct {
    listenAddr      string
    upstreamAddr    string
    dialTimeout     time.Duration
    idleTimeout     time.Duration
    tcpKeepAliveSec int
    maxConns        int
}

func loadConfig() *config {
    cfg := &config{}
    // Flags with env fallbacks
    flag.StringVar(&cfg.listenAddr, "listen", envDefault("LISTEN_ADDR", "0.0.0.0:7022"), "Local listen address (host:port)")
    flag.StringVar(&cfg.upstreamAddr, "upstream", envDefault("UPSTREAM_ADDR", "github.com:22"), "Upstream SSH address (host:port), e.g. github.com:22 or ssh.github.com:443")
    dt := parseDurationEnv("DIAL_TIMEOUT", 5*time.Second)
    it := parseDurationEnv("IDLE_TIMEOUT", 0)
    flag.DurationVar(&cfg.dialTimeout, "dial-timeout", dt, "Timeout for dialing upstream")
    flag.DurationVar(&cfg.idleTimeout, "idle-timeout", it, "Optional per-connection idle timeout (0 to disable)")
    tk := envDefault("TCP_KEEPALIVE", "30") // seconds; 0 disables
    ka, _ := strconv.Atoi(tk)
    cfg.tcpKeepAliveSec = ka
    mcEnv := envDefault("MAX_CONNS", "0")
    mc, _ := strconv.Atoi(mcEnv)
    cfg.maxConns = mc
    flag.Parse()
    return cfg
}

type limitListener struct {
    net.Listener
    sem chan struct{}
}

func (l *limitListener) Accept() (net.Conn, error) {
    if l.sem != nil {
        l.sem <- struct{}{}
    }
    c, err := l.Listener.Accept()
    if err != nil {
        if l.sem != nil {
            <-l.sem
        }
        return nil, err
    }
    return &countedConn{Conn: c, release: func() {
        if l.sem != nil {
            <-l.sem
        }
    }}, nil
}

type countedConn struct {
    net.Conn
    once    sync.Once
    release func()
}

func (c *countedConn) Close() error {
    var err error
    c.once.Do(func() {
        err = c.Conn.Close()
        if c.release != nil {
            c.release()
        }
    })
    return err
}

func main() {
    log.SetFlags(log.LstdFlags | log.Lmicroseconds)
    cfg := loadConfig()
    log.Printf("ssh-forward: listen=%s upstream=%s dial-timeout=%s idle-timeout=%s keepalive=%ds max-conns=%d go=%s", cfg.listenAddr, cfg.upstreamAddr, cfg.dialTimeout, cfg.idleTimeout, cfg.tcpKeepAliveSec, cfg.maxConns, runtime.Version())

    baseLn, err := net.Listen("tcp", cfg.listenAddr)
    if err != nil {
        log.Fatalf("listen error on %s: %v", cfg.listenAddr, err)
    }
    var ln net.Listener = baseLn
    if cfg.maxConns > 0 {
        ln = &limitListener{Listener: baseLn, sem: make(chan struct{}, cfg.maxConns)}
    }

    ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
    defer stop()

    var wg sync.WaitGroup
    go func() {
        <-ctx.Done()
        _ = ln.Close()
    }()

    for {
        clientConn, err := ln.Accept()
        if err != nil {
            if errors.Is(err, net.ErrClosed) || strings.Contains(err.Error(), "use of closed network connection") {
                break
            }
            log.Printf("accept error: %v", err)
            continue
        }
        wg.Add(1)
        go func(c net.Conn) {
            defer wg.Done()
            handleConn(ctx, c, cfg)
        }(clientConn)
    }
    wg.Wait()
    log.Printf("ssh-forward: shutdown complete")
}

func handleConn(ctx context.Context, client net.Conn, cfg *config) {
    id := time.Now().UnixNano()
    ra := client.RemoteAddr().String()
    log.Printf("[%d] accepted %s", id, ra)

    // Optional TCP keepalive on accepted conn
    if tc, ok := client.(*net.TCPConn); ok {
        if cfg.tcpKeepAliveSec > 0 {
            _ = tc.SetKeepAlive(true)
            _ = tc.SetKeepAlivePeriod(time.Duration(cfg.tcpKeepAliveSec) * time.Second)
        }
    }

    d := net.Dialer{Timeout: cfg.dialTimeout}
    upstream, err := d.DialContext(ctx, "tcp", cfg.upstreamAddr)
    if err != nil {
        log.Printf("[%d] dial upstream %s failed: %v", id, cfg.upstreamAddr, err)
        _ = client.Close()
        return
    }

    if tc, ok := upstream.(*net.TCPConn); ok {
        if cfg.tcpKeepAliveSec > 0 {
            _ = tc.SetKeepAlive(true)
            _ = tc.SetKeepAlivePeriod(time.Duration(cfg.tcpKeepAliveSec) * time.Second)
        }
    }

    // Deadline management for idle connections
    if cfg.idleTimeout > 0 {
        deadline := time.Now().Add(cfg.idleTimeout)
        _ = client.SetDeadline(deadline)
        _ = upstream.SetDeadline(deadline)
    }

    // Bi-directional copy with half-close support
    var wg sync.WaitGroup
    proxy := func(dst, src net.Conn, dir string) {
        defer wg.Done()
        n, err := io.Copy(dst, src)
        if err != nil && !errors.Is(err, net.ErrClosed) && !strings.Contains(err.Error(), "use of closed network connection") {
            log.Printf("[%d] copy %s error after %d bytes: %v", id, dir, n, err)
        }
        if c, ok := dst.(interface{ CloseWrite() error }); ok {
            _ = c.CloseWrite()
        } else {
            _ = dst.Close()
        }
    }

    log.Printf("[%d] connected upstream %s", id, cfg.upstreamAddr)
    wg.Add(2)
    go proxy(upstream, client, "client->upstream")
    go proxy(client, upstream, "upstream->client")
    wg.Wait()

    _ = upstream.Close()
    _ = client.Close()
    log.Printf("[%d] closed %s", id, ra)
}
