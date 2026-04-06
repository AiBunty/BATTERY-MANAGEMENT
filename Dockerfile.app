FROM php:8.1-cli

RUN docker-php-ext-install pdo_mysql

WORKDIR /var/www/html

EXPOSE 8000

CMD ["php", "-S", "0.0.0.0:8000", "-t", "public"]
