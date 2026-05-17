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

# 执行前端编译，生成静态文件输出到 server/web 目录
RUN cd web && npm run build

# ==========================================
# 阶段 2: 后端编译 (🔥 升级至最新版 Golang 镜像)
# ==========================================
# 使用 golang:alpine (不指定 1.21) 以获取最新的 Go 1.24/1.25 编译器，解决 go.mod 声明 1.25.0 导致的报错
FROM golang:alpine AS backend-builder
# 安装编译 Go 项目及 SQLite 驱动可能需要的工具包
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
# -tags ui : 开启 ui 编译标签，把刚才拷贝的前端静态文件使用 go:embed 直接打包嵌入二进制中
# -trimpath : 移除编译后二进制里的本地文件路径信息
# -ldflags "-s -w" : 压缩二进制体积，移除调试信息和符号表
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
# 安装必要的系统证书及全球时区数据
RUN apk add --no-cache ca-certificates tzdata

WORKDIR /app

# 从构建阶段 (backend-builder) 拷贝最终编译好的单文件可执行程序
COPY --from=backend-builder /app/server/ovh-server .

# 创建数据挂载目录，用于存放 SQLite 数据库 (data/sniper.db) 和应用日志
RUN mkdir -p /app/data

# 暴露容器内部监听的端口 (后端默认端口)
EXPOSE 19998

# 将数据目录声明为匿名卷，防止容器重建时数据丢失
VOLUME ["/app/data"]

# 容器启动运行命令
CMD ["./ovh-server"]
