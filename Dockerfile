# --- 第一階段：編譯環境 ---
FROM alpine:latest AS builder

RUN apk add --no-cache \
    bash build-base autoconf automake libtool pkgconfig git gettext-dev \
    pango-dev cairo-dev libxml2-dev glib-dev groff perl-dev \
    dos2unix help2man m4 net-snmp-dev mariadb-dev openssl-dev wget \
    mariadb tzdata  # 這裡增加 mariadb 以生成時區 SQL

WORKDIR /src

# 1. 生成時區 SQL 檔案 (供 Entrypoint 使用)
RUN mariadb-tzinfo-to-sql /usr/share/zoneinfo > /src/timezone.sql

# 2. 編譯 RRDTool
RUN git clone --depth 1 https://github.com/oetiker/rrdtool-1.x.git rrdtool && \
    cd rrdtool && ./bootstrap && \
    ./configure --prefix=/usr \
    --disable-perl --disable-python --disable-tcl --disable-lua --disable-ruby \
    --disable-docs --disable-nls && \
    make -j$(nproc) && make install-strip

# 3. 編譯 Spine
RUN git clone --depth 1 https://github.com/Cacti/spine.git spine && \
    cd spine && \
    sed -i 's/#define BIG_BUFSIZE 65535/#define BIG_BUFSIZE 16384/' spine.h && \
    sed -i 's/#define LOGSIZE 65535/#define LOGSIZE 16384/' spine.h && \
    ./bootstrap && \
    export CFLAGS="-g -O0 -fno-stack-protector" && \
    export LDFLAGS="-Wl,-z,stack-size=2097152" && \
    ./configure --with-mysql --with-snmp=/usr && \
    make -j$(nproc) && make install

# --- 第二階段：執行環境 ---
FROM alpine:latest

ENV CACTI_VERSION=1.2.30

# 安裝運行環境 (保持輕量)
RUN apk add --no-cache \
    apache2 php83-apache2 php83-session php83-mysqli php83-sockets php83-gd \
    php83-gettext php83-gmp php83-xml php83-mbstring php83-posix php83-ldap \
    php83-ctype php83-zlib php83-simplexml php83-pdo_mysql php83-cli \
    php83-intl php83-pcntl php83-snmp \
    net-snmp net-snmp-tools mariadb-client mariadb-connector-c \
    curl tzdata bc bash perl procps \
    ttf-dejavu fontconfig \
    # --- 關鍵修正：加入 RRDTool 繪圖所需的執行期函式庫 ---
    pango cairo glib libxml2 \
    && ln -sf /usr/bin/php83 /usr/bin/php \
    && rm -f /var/www/localhost/htdocs/*

# 下載 Cacti
WORKDIR /var/www/localhost/htdocs
RUN curl -L https://www.cacti.net/downloads/cacti-${CACTI_VERSION}.tar.gz | tar zx --strip-components=1 \
    && rm -rf docs/ \
    && find . -name "*.po" -delete

# 3. 處理中文字型 (關鍵瘦身步驟)
# 這裡我們下載一個輕量化的繁體中文字型 (例如：源石黑體或類似開源字型)
# 或是如果你本地有 .ttf，改用 COPY 也可以
RUN mkdir -p /usr/share/fonts/chinese && \
    curl -L -o /usr/share/fonts/chinese/font.ttf https://github.com/googlefonts/noto-cjk/raw/main/Sans/OTF/TraditionalChinese/NotoSansCJKtc-Regular.otf || \
    echo "Font download failed, please use COPY instead" 
# 註：建議在本地備好 font.ttf 使用 COPY /local_font.ttf /usr/share/fonts/chinese/font.ttf 體積最精確
RUN fc-cache -fv

# 複製編譯成品與時區 SQL
COPY --from=builder /src/timezone.sql /usr/share/cacti/timezone.sql
COPY --from=builder /usr/bin/rrd* /usr/bin/
COPY --from=builder /usr/lib/librrd* /usr/lib/
COPY --from=builder /usr/share/rrdtool /usr/share/rrdtool
COPY --from=builder /usr/local/spine /usr/local/spine

# 配置 Spine 與語系
COPY zh-TW.mo ./locales/LC_MESSAGES/zh-TW.mo
#COPY zh-TW.po ./locales/po/zh-TW.po
COPY fix-cacti.sql /fix-cacti.sql
RUN cp /usr/local/spine/etc/spine.conf.dist /usr/local/spine/etc/spine.conf \
    && chown root:root /usr/local/spine/bin/spine \
    && chmod +s /usr/local/spine/bin/spine \
    && chown -R apache:apache /var/www/localhost/htdocs/

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 80
ENTRYPOINT ["/entrypoint.sh"]

