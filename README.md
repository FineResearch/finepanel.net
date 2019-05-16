# Finepanel

## Local setup

First you need to have **Docker** installed on your local machine.

1. Clone the repo locally.
2. Create a symlink for the **docker-compose.override.yml** file. ([More on docker compose files](https://docs.docker.com/compose/extends/#understanding-multiple-compose-files)).
To create the symlink needed execute `ln -s docker-compose.override.dev.yml docker-compose.override.yml`.
3. Execute `docker-compose up`. This will build the images needed and then start the services.

   To use docker detached run the above command with `-d` flag. This will start it as a deamon and will not block the console.
   The default dev configuration creates the database on postgres called `finepanel_dev`, user `postgres` and pass `postgres`.
   This is specified on the `docker-compose.yml` file.
4. Then create the database inside postgres container: `docker-compose run app bundle exec rails db:create`.
5. Execute migrations: `docker-compose run app bundle exec rails db:create`.


## Deploy

1. SSH to the server forwarding the agent to the user `mooveit`: `ssh -A mooveit@staging.finepanel.net`.
 *Ask on slack to include your public key to the `mooveit` user.*

2. Inside `~/finepanel` do a pull from the github repo.
3. Execute `docker-compose down`.
4. Execute `docker-compose up -d --build`.
 This will rebuild the image if it's needed, such as if the Dockerfile changed.
5. Go to <a href="http://staging.finepanel.net" target="_blank">http://staging.finepanel.net</a> and check for the new version.

## Docker usage


Basic Docker knowledge would be good to have. You can check Docker documentation to have more insight on how Dockerfiles or docker-compose works.

### Some basic stuff:

To run any command on a container use the following command `docker-compose run <container name found inside docker-compose.yml> <command>`.
[More on `run` command](https://docs.docker.com/compose/reference/run/)

For example, if you want to have a shell inside the app container do the following: `docker-compose run app bash`
Or if you want to load a dump to the database you can include the dump file inside the `data/` folder which is mounted as a volume to the postgres container
and do the following: `docker-compose run postgres bash` and inside there use [`psql`](https://www.postgresql.org/docs/8.1/backup.html) for example.
[More on volumes](https://docs.docker.com/storage/volumes/).
