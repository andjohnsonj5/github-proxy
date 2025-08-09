FROM openresty/openresty:1.25.3.1-0-bullseye

# Copy our nginx.conf as the main config
COPY openresty/nginx.conf /usr/local/openresty/nginx/conf/nginx.conf

EXPOSE 7070

# Run in foreground
CMD ["openresty","-g","daemon off;"]
