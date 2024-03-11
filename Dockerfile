FROM postgres:16.2
RUN apt-get update && apt-get install -y curl


RUN apt-get -y install postgresql-15-cron
RUN echo "shared_preload_libraries='pg_cron'" >> /usr/share/postgresql/postgresql.conf.sample
RUN echo "cron.database_name='your_db_name'" >> /usr/share/postgresql/postgresql.conf.sample