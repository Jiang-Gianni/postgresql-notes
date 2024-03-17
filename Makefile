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

logs:
	docker logs $$(docker ps -a -q --filter ancestor=postgres)

fc:
	d2 img/optimizationFlowchart.d2 img/optimizationFlowchart.svg

psql:
	psql -d postgresql://root:my-secret-pw@localhost:5432/mydb?sslmode=disable -t -P linestyle=old-ascii

d2f:
	psql -d postgresql://root:my-secret-pw@localhost:5432/mydb?sslmode=disable -f d2.sql -t -P linestyle=old-ascii > d2.d2

d2q:
	psql -d postgresql://root:my-secret-pw@localhost:5432/mydb?sslmode=disable -f d2.sql -t -P linestyle=old-ascii

d2:
	d2 --layout=elk d2.d2 d2.svg

mdf:
	psql -d postgresql://root:my-secret-pw@localhost:5432/mydb?sslmode=disable -f md.sql -t -P linestyle=old-ascii > md.md