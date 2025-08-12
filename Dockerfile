# ===== 构建阶段 =====（构建应用）
# 使用带Maven的官方镜像（小尺寸Alpine基础）
FROM maven:3.8.6-eclipse-temurin-17-alpine AS builder

# 设置工作目录
WORKDIR /app

# 先复制POM文件（利用Docker层缓存）
COPY pom.xml .


# 在mvn命令前添加阿里云镜像
RUN sed -i 's|https://repo.maven.apache.org|https://maven.aliyun.com/repository/public|g' /usr/share/maven/conf/settings.xml

# 下载依赖（离线模式加速后续构建）
# RUN mvn dependency:go-offline -B
# 暂时使用简单的依赖下载，避免超时
RUN mvn dependency:resolve -B

# 复制源代码
COPY src ./src

# 构建应用（跳过测试）
RUN mvn package -DskipTests

# ===== 运行阶段 =====（最小化运行时镜像）
# 使用官方JRE镜像（比JDK小60%）
FROM eclipse-temurin:24-jre-alpine

# 设置容器内工作目录
WORKDIR /app

# 从构建阶段复制JAR文件
COPY --from=builder /app/target/*.jar ./app.jar

# ===== 安全加固 =====
# 创建非root用户（必须！）
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# 设置时区（中国时区）
ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# 创建日志目录并授权
RUN mkdir -p /logs && chown appuser:appgroup /logs
VOLUME /logs

# 切换用户（禁止root运行）
USER appuser

# ===== 运行配置 =====
# 暴露端口（Spring Boot默认8080）
EXPOSE 8080

# 健康检查（使用Spring Boot Actuator）
HEALTHCHECK --interval=30s --timeout=3s \
  CMD wget -qO- http://localhost:8080/actuator/health || exit 1

# 启动命令（限制内存+优化GC）
ENTRYPOINT ["java","-Xmx256m","-XX:+UseZGC","-Djava.security.egd=file:/dev/./urandom","-Dspring.profiles.active=prod","-jar", "app.jar"]