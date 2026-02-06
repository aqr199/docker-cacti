# 在 docker 環境架設 cacti 服務

使用 alpine:3.21 建立 cacti 服務

# 安裝軟體

apache, php 8.3, cacti 1.2.30


# 編譯軟體

從 github 下載 rrdtool, spine 重新編譯

!!! rrdtool 圖片有問題, 從 github 下載重新編譯, 才能正常顯示

!!! spine 使用的陣列尺寸, 超過 alpine 上限, 會出現記憶體使用超過問題

!!! spine 連線 mariadb, 會遇到 TLS 連線錯誤, 設定檔內 DB_UseSSL 參數沒有作用。

# 修正

!!! 缺少 host_errors 資料表

因為 spine 使用最新版本, 缺少 host_errors 資料表, 在 entrypoint.sh 透過 fix-cacti.sql 建立資料表

!!! 繁體中文亂碼

在 Dockerfile 下載字體

!!! 時區資料

為了生成時區資料, 安裝了網站運作不需要的軟體, 增加了 image 容量。
在 Dockerfile builder 階段, 匯出 timezone 資料, 到正式環境時匯入。

```
mariadb-tzinfo-to-sql /usr/share/zoneinfo > /src/timezone.sql
```

!!! 繁體中文語系修正

全形百分比符號更換成半形百分比符號

zh-TW.mo
zh-TW.po


#
