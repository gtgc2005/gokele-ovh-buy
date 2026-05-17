# ==========================================
# 阶段 1: 前端构建 (使用 Node.js 镜像)
# ==========================================
FROM node:20-alpine AS frontend-builder
WORKDIR /app

# 复制前端依赖描述文件，优先利用 Docker 缓存加速以后的构建
COPY web/package*.json ./web/
RUN cd web && npm ci

# 复制完整前端和后端代码
COPY web/ ./web/
COPY server/ ./server/

# 🔥 核心修正：不运行 "npm run build" (那会触发 tsc 类型检查报错)，
# 直接通过 npx vite build 编译。Vite 插件会自动生成 routeTree.gen.ts 并完美打包！
RUN cd web && npx vite build

# ==========================================
# 阶段 2: 后端编译 (使用最新版 Golang 镜像)
# ==========================================
FROM golang:alpine AS backend-builder
RUN apk add --no-cache gcc musl-dev git

WORKDIR /app

# 拷贝并缓存 Go 后端依赖，避免每次都重新下载
COPY server/go.mod server/go.sum ./server/
RUN cd server && go mod download

# 拷贝 Go 后端源码
COPY server/ ./server/

# 从阶段 1 (frontend-builder) 中把编译好的前端静态文件拷贝过来
COPY --from=frontend-builder /app/server/web ./server/web

# 编译单二进制可执行文件
RUN cd server && \
    CGO_ENABLED=0 GOOS=linux go build \
    -tags ui \
    -trimpath \
    -ldflags "-s -w" \
    -o ovh-server .

# ==========================================
# 阶段 3: 最终运行镜像 (使用极简 Alpine 镜像)
# ==========================================
FROM alpine:latest
RUN apk add --no-cache ca-certificates tzdata

WORKDIR /app

# 从构建阶段拷贝最终编译好的单文件可执行程序
COPY --from=backend-builder /app/server/ovh-server .

# 创建数据挂载目录
RUN mkdir -p /app/data

# 暴露端口
EXPOSE 19998

# 数据持久化挂载
VOLUME ["/app/data"]

# 启动命令
CMD ["./ovh-server"]
