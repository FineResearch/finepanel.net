# Finepanel

## Local setup

First you need to have **Docker** installed on your local machine.

1. Clone the repo locally.
2. `cd finepanel`
3. Create .env file based on .env.sample.
4. Run `bin/start` to start all containers with the services
5.  Create basic data: inside API container run:
  - `bundle exec rails newsfeed:create_specialties`  => Create all allowed specialties
  - `bundle exec rails newsfeed:create_articles SPECIALTY=xxx`(xxx is each one of the specialties slug for example infectious_diseases) => Create all articles by specialty
6. Finally, you need to create some tests user, contact your project manager to get this information.

## Deploy
The application uses GitHub Actions to make the deploys only for the staging environment, to the production environment is manually.

## Docker usage

Basic Docker knowledge would be good to have. You can check Docker documentation to have more insight on how Dockerfiles or docker-compose works.

### Some basic stuff:

To run any command on a container use the following command `docker-compose run <container name found inside docker-compose.yml> <command>`.
[More on `run` command](https://docs.docker.com/compose/reference/run/)

For example, if you want to have a shell inside the app container do the following: `docker-compose run app bash`
Or if you want to load a dump to the database you can include the dump file inside the `data/` folder which is mounted as a volume to the postgres container
and do the following: `docker-compose run postgres bash` and inside there use [`psql`](https://www.postgresql.org/docs/8.1/backup.html) for example.
[More on volumes](https://docs.docker.com/storage/volumes/).


## Caveats for Apple M2 chip users
There some problems when run `bin/start` and we're getting some errors when compiling gem dependencies, to avoid those errors should edit the `Dockerfile.local` file
adding some packages. Find this line:
```
RUN apk add --no-cache nodejs build-base postgresql-dev libxml2-dev libxslt-dev sqlite-dev tzdata \
  git openssh postgresql
```
And add these packages `gcc libtool linux-headers`, so should looks like:
```
RUN apk add --no-cache nodejs build-base postgresql-dev libxml2-dev libxslt-dev sqlite-dev tzdata \
  git openssh postgresql gcc libtool linux-headers
```
Note: Please, don't commit those changes.