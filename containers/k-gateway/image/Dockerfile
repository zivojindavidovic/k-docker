FROM eclipse-temurin:25.0.4.1_1-jdk

# Razvojna slika: kod projekta je bind mount na /app (docker-compose.yaml), a
# Gradle distribucija i zavisnosti su u volumenu na /home/app/.gradle, pa
# kontejner pokrece ./gradlew bootRun nad izvornim kodom. Posle izmene koda:
# docker compose restart k-gateway.

# Gradle radi kao korisnik sa uid/gid hosta, da build/ i .gradle/ u projektu
# budu vlasnistvo host korisnika. Osnovna slika (Ubuntu) vec ima korisnika
# "ubuntu" sa uid 1000, zato se on uklanja.
ARG HOST_UID=1000
ARG HOST_GID=1000
RUN (userdel -r ubuntu 2>/dev/null || true) \
    && groupadd -g ${HOST_GID} app \
    && useradd -m -u ${HOST_UID} -g app app \
    && mkdir -p /home/app/.gradle \
    && chown -R app:app /home/app

ENV GRADLE_USER_HOME=/home/app/.gradle
WORKDIR /app
USER app

CMD ["./gradlew", "bootRun", "--no-daemon", "--console=plain"]

EXPOSE 9090
