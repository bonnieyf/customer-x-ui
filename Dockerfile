# 第一階段：編譯階段 (使用包含 Go 環境的鏡像)
FROM golang:1.21 AS builder

# 安裝編譯 CGO (SQLite) 必要的 GCC 工具
RUN apt-get update && apt-get install -y gcc libc6-dev

WORKDIR /root
COPY . .

# 執行編譯：開啟 CGO，針對 Linux AMD64 架構
RUN CGO_ENABLED=1 GOOS=linux GOARCH=amd64 go build -o main main.go


# 第二階段：執行階段 (使用極簡鏡像以縮小體積)
FROM debian:12-slim

# 安裝運行時必要的套件
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
    && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

WORKDIR /root

# 從 builder 階段將編譯好的執行檔複製過來
COPY --from=builder /root/main /root/x-ui
# 複製 bin 目錄 (包含 xray 核心)
COPY bin /root/bin

# 設定持久化空間
VOLUME [ "/etc/x-ui" ]

# 啟動指令
CMD [ "./x-ui" ]