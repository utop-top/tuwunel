# 建议使用稳定的大版本标签，防止特定小版本号失效
FROM rust:1-slim-bookworm AS chef

# 预安装 cargo-chef
RUN cargo install cargo-chef --locked

# 安装核心编译依赖
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        cmake \
        libclang-dev \
        pkg-config \
        libssl-dev \
        liburing-dev \
        git && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src/app


# Planner Stage - 生成依赖树
FROM chef AS planner
COPY . .
RUN cargo chef prepare --recipe-path recipe.json


# Builder Stage - 利用缓存编译
FROM chef AS builder
COPY --from=planner /usr/src/app/recipe.json recipe.json
ENV CARGO_NET_GIT_FETCH_WITH_CLI=true

# 编译依赖
RUN --mount=type=cache,target=/usr/local/cargo/registry,sharing=locked \
    --mount=type=cache,target=/usr/local/cargo/git,sharing=locked \
    --mount=type=cache,target=/usr/src/app/target,sharing=locked \
    cargo chef cook --release --recipe-path recipe.json

# 拷贝源码并编译最终二进制文件
COPY . .
RUN --mount=type=cache,target=/usr/local/cargo/registry,sharing=locked \
    --mount=type=cache,target=/usr/local/cargo/git,sharing=locked \
    --mount=type=cache,target=/usr/src/app/target,sharing=locked \
    cargo build --release && \
    cp /usr/src/app/target/release/tuwunel /tmp/tuwunel


# Runtime Stage - 极简运行环境
FROM debian:bookworm-slim

# 安装运行时依赖：追加 libssl3（若有 sqlite 需求建议加上 libsqlite3-0）
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        libssl3 \
        liburing2 \
        curl && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /tmp/tuwunel /usr/local/bin/tuwunel
COPY tuwunel-example.toml /etc/tuwunel.toml

# 声明挂载点和工作目录
VOLUME ["/var/lib/tuwunel"]
WORKDIR /var/lib/tuwunel

# 端口暴露
EXPOSE 6167

CMD ["tuwunel", "-c", "/etc/tuwunel.toml"]
