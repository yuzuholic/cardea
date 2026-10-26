# yuzuholic/cardea — a launcher, not an all-in-one: it carries the lab compose file and a
# current docker compose, and starts the stack's official images beside itself.
FROM docker:29.9.0-cli

COPY lab/docker-compose.yml /cardea/compose.yml
COPY cardea.sh /usr/local/bin/cardea
RUN chmod +x /usr/local/bin/cardea

ENTRYPOINT ["/usr/local/bin/cardea"]
