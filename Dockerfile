# ---- build ----
FROM eclipse-temurin:21-jdk AS build
WORKDIR /src
# 의존성 레이어를 먼저 받아 캐시를 살립니다
COPY gradlew settings.gradle build.gradle ./
COPY gradle ./gradle
RUN chmod +x gradlew && ./gradlew --no-daemon dependencies > /dev/null 2>&1 || true
COPY src ./src
RUN ./gradlew --no-daemon bootJar -x test && cp build/libs/*-SNAPSHOT.jar /app.jar

# ---- run ----
FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=build /app.jar app.jar
ENV PORT=3000
EXPOSE 3000
# exec 형식이라 java 가 PID 1 이 되어 SIGTERM 을 직접 받습니다 (graceful shutdown)
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=70", "-jar", "app.jar"]
