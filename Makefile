sd:
	@sudo systemctl start docker

pg:
	docker run --rm -it --name local-postgres -p 5432:5432 -e POSTGRES_PASSWORD=my-secret-pw -e POSTGRES_USER=root -e POSTGRES_DB=mydb -d postgres

kp:
	docker kill $$(docker ps -a -q --filter ancestor=postgres) && docker container prune

up:
	dbmate up && docker exec local-postgres pg_dump --inserts mydb > ./db/schema.sql

down:
	dbmate down && docker exec local-postgres pg_dump --inserts mydb > ./db/schema.sql

dc:
	docker compose up --detach