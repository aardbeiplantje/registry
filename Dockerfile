FROM alpine:latest AS proxy-runtime
RUN apk add --no-cache nginx nginx-mod-http-auth-jwt nginx-mod-http-headers-more nginx-mod-http-lua
COPY ./nginx.conf /etc/nginx/nginx.conf
RUN ln -s /certs/ /etc/nginx/certs
RUN nginx -t -c /etc/nginx/nginx.conf
ENTRYPOINT ["/usr/sbin/nginx", "-c", "/etc/nginx/nginx.conf", "-g", "daemon off;"]
