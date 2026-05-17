# ==========================================
# 阶段 1: 前端构建 (Node.js)
# ==========================================
FROM node:20-alpine AS frontend-builder
WORKDIR /app

# 复制依赖描述文件，利用 Docker 缓存机制加速构建
COPY web/package*.json ./web/
RUN cd web && npm ci

# 复制完整前端和后端框架（确保 Vite 构建时相对路径 ../server/web 生效）
COPY web/ ./web/
COPY server/ ./server/

# 执行前端构建，生成静态文件到 server/web 目录
RUN cd web && npm run build

# ==========================================
# 阶段 2: 后端构建 (Golang)
# ==========================================
FROM golang:1.21-alpine AS backend-builder
RUN apk add --no-cache gcc musl-dev git

WORKDIR /app

# 缓存 Go 依赖
COPY server/go.mod server/go.sum ./server/
RUN cd server && go mod download

# 复制 Go 源码
COPY server/ ./server/

# 从阶段 1 拷贝构建好的前端静态文件（以防路径未自动生成）
COPY --from=frontend-builder /app/server/web ./server/web

# 编译单二进制文件（启用 ui 标签将前端打包进二进制）
RUN cd server && \
    CGO_ENABLED=0 GOOS=linux go build \
    -tags ui \
    -trimpath \
    -ldflags "-s -w" \
    -o ovh-server .

# ==========================================
# 阶段 3: 最终运行镜像 (Alpine)
# ==========================================
FROM alpine:latest
RUN apk add --no-cache ca-certificates tzdata

WORKDIR /app

# 从构建阶段拷贝编译好的二进制
COPY --from=backend-builder /app/server/ovh-server .

# 创建数据挂载目录（SQLite 和日志存储位置）
RUN mkdir -p /app/data

# 暴露容器端口
EXPOSE 19998

# 挂载数据卷以实现持久化
VOLUME ["/app/data"]

# 启动命令
CMD ["./ovh-server"]
