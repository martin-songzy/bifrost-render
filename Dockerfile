# 基于官方固定版本镜像，注入 config.json（纯配置，无任何密钥）
FROM docker.io/maximhq/bifrost:v2.4.0
COPY config/config.json /app/data/config.json