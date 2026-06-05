FROM httpd:2.4-alpine

RUN sed -i \
    -e 's|^#\(LoadModule rewrite_module\)|\1|' \
    -e 's|^#\(LoadModule expires_module\)|\1|' \
    -e 's|^#\(LoadModule deflate_module\)|\1|' \
    -e 's|^#\(LoadModule headers_module\)|\1|' \
    /usr/local/apache2/conf/httpd.conf

COPY images/apache-static/vhost.conf /usr/local/apache2/conf/extra/vhost.conf

RUN echo "Include conf/extra/vhost.conf" >> /usr/local/apache2/conf/httpd.conf

RUN echo "ServerName localhost" >> /usr/local/apache2/conf/httpd.conf

WORKDIR /usr/local/apache2/htdocs
