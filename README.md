# NAT-Haproxy
HAProxy + Nginx Load Balancing and NAT Network Infrastructure Project using Rocky Linux and VirtualBox
[README_NAT_HAProxy_Nginx (1).md](https://github.com/user-attachments/files/33860143/README_NAT_HAProxy_Nginx.1.md)
# NAT + HAProxy + Nginx 로드밸런싱 실습

> Rocky Linux / VirtualBox 기반 실습. **WEB1~3 → HAProxy·Nginx LB → NAT → 외부 PC 테스트** 순서로 진행합니다. 아래 IP는 실습 환경 기준이며, 다른 환경에서는 IP와 인터페이스 이름을 변경해야 합니다.

## 0. 네트워크 구조 및 실습 환경

```text
                 [외부 PC: 192.168.0.x]
                            |
              +-------------+-------------+
              | NAT: 192.168.0.235       |
              | 80 -> 192.168.56.101:80  |
              | 8080 -> .56.101:8080     |
              +-------------+-------------+
                            |
              +-------------+-------------+
              | LB VM: 192.168.56.101    |
              | HAProxy :80              |
              | Nginx   :8080            |
              | (두 LB는 병렬 운영)       |
              +-------------+-------------+
                            |
                 +----------+----------+
                 |          |          |
           WEB1 :80     WEB2 :80    WEB3 :80
          .56.103       .56.104     .56.105
```

| 서버 | IP / 포트 | 역할 |
| --- | --- | --- |
| NAT | `192.168.0.235` | 외부 요청을 내부 LB로 DNAT |
| HAProxy | `192.168.56.101:80` | HTTP 로드밸런싱 |
| Nginx LB | `192.168.56.101:8080` | HTTP 로드밸런싱 |
| WEB1 | `192.168.56.103:80` | 서버 식별 HTML 제공 |
| WEB2 | `192.168.56.104:80` | 서버 식별 HTML 제공 |
| WEB3 | `192.168.56.105:80` | 서버 식별 HTML 제공 |

**선행 조건:** VM이 생성되고 Rocky Linux가 설치되어 있어야 합니다. NAT는 외부망(브리지)과 내부망(Host-Only) 양쪽에 연결되어야 하며, LB·WEB 서버는 같은 내부망(`192.168.56.0/24`)에서 통신 가능해야 합니다. 실습의 NAT 내부망 출력 인터페이스는 `enp0s8`입니다. `root` 또는 `sudo` 권한으로 실행합니다.

## 1. WEB 서버 3대 설치 (WEB1 → WEB2 → WEB3 각각 반복)

**실행 위치:** 해당 WEB 서버 VM. 한 번에 한 서버씩 접속합니다.

```bash
# 1-1. NAT 서버 등 SSH 접속 가능한 호스트에서 원하는 WEB 서버 하나 선택
ssh root@192.168.56.103          # WEB1
# ssh root@192.168.56.104        # WEB2
# ssh root@192.168.56.105        # WEB3

# 1-2. 접속한 서버 및 네트워크 확인
hostname                          # 현재 서버 이름
ip -br addr                       # 인터페이스·IP 확인
ping -c 4 192.168.56.101         # 로드밸런서와 통신 확인

# 1-3. Nginx 설치·실행
dnf install -y nginx              # Nginx 패키지 설치
nginx -v                          # 설치된 버전 확인
systemctl enable --now nginx     # 즉시 실행 + 부팅 자동 시작
systemctl is-active nginx        # active인지 확인
ss -nltp | grep ':80'            # TCP 80번 포트 리스닝 확인
```

### 1-4. WEB별 식별 페이지 만들기

**각 WEB 서버에서 실행:** 서버 번호와 IP를 해당 서버에 맞게 지정합니다. 아래 코드는 세 서버에 **같은 디자인**을 적용하고 제목/서버 번호만 변경합니다.

```bash
# WEB1에서는 다음 두 변수 사용
WEB_NUM=1
WEB_IP=192.168.56.103

# WEB2에서는 다음 두 변수로 변경
# WEB_NUM=2
# WEB_IP=192.168.56.104

# WEB3에서는 다음 두 변수로 변경
# WEB_NUM=3
# WEB_IP=192.168.56.105

# 1-4-1. 기존 파일이 있으면 백업
[ ! -f /usr/share/nginx/html/index.html ] || cp -a /usr/share/nginx/html/index.html /usr/share/nginx/html/index.html.bak

# 1-4-2. HTML 생성 (WEB_NUM/WEB_IP 값이 반영됨)
cat > /usr/share/nginx/html/index.html <<EOF_HTML
<!doctype html>
<html lang="ko">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>HAProxy 실습 - WEB SERVER ${WEB_NUM}</title>
  <style>
    :root { color-scheme: dark; }
    * { box-sizing: border-box; }
    body { margin: 0; min-height: 100vh; display: grid; place-items: center; font-family: system-ui, -apple-system, "Segoe UI", sans-serif; background: radial-gradient(ellipse at top, #1d2b49 0%, #0b1020 58%, #070a12 100%); color: #f4f7fb; padding: 24px; }
    main { width: min(720px, 100%); padding: clamp(28px, 6vw, 56px); border: 1px solid #ffffff20; border-radius: 28px; background: #111827d9; box-shadow: 0 24px 80px #0008; }
    .eyebrow { color: #a9b7d0; letter-spacing: .16em; text-transform: uppercase; font-size: 12px; font-weight: 700; }
    h1 { font-size: clamp(32px, 6vw, 52px); line-height: 1.08; margin: 14px 0; }
    .server { display: inline-flex; align-items: center; gap: 10px; margin: 18px 0 8px; padding: 10px 15px; border-radius: 999px; background: #5eead420; border: 1px solid #5eead480; color: #5eead4; font-weight: 800; }
    .dot { width: 9px; height: 9px; border-radius: 50%; background: #5eead4; box-shadow: 0 0 14px #5eead4; }
    p { color: #b8c3d6; line-height: 1.7; }
    .info { margin-top: 28px; padding: 18px 20px; border-radius: 16px; background: #ffffff08; border: 1px solid #ffffff12; }
    .info strong { display: block; color: #fff; margin-bottom: 6px; }
    .row { display: flex; flex-wrap: wrap; justify-content: space-between; gap: 12px; margin-top: 28px; color: #8290a8; font-size: 13px; }
    button { border: 0; border-radius: 12px; padding: 12px 16px; background: #f4f7fb; color: #101827; font-weight: 800; cursor: pointer; }
    button:hover { opacity: .88; }
  </style>
</head>
<body>
  <main>
    <div class="eyebrow">Load Balancing Lab · HAProxy / Nginx</div>
    <h1>웹 서버<br>정상 응답 중</h1>
    <div class="server"><span class="dot"></span>WEB SERVER ${WEB_NUM} · WEB-0${WEB_NUM}</div>
    <p>이 페이지는 ${WEB_NUM}번째 웹 서버(${WEB_IP})에서 제공하는 실습용 페이지입니다.</p>
    <section class="info"><strong>현재 응답한 서버</strong><span>WEB SERVER ${WEB_NUM} (WEB-0${WEB_NUM})</span></section>
    <div class="row"><span>응답 확인 시간: <span id="time">-</span></span><button onclick="location.reload()">새로고침 테스트</button></div>
  </main>
  <script>document.getElementById("time").textContent = new Date().toLocaleString("ko-KR");</script>
</body>
</html>
EOF_HTML

# 1-4-3. 파일 SELinux 컨텍스트 복원
restorecon -v /usr/share/nginx/html/index.html


# 1-4-4. HTTP 방화벽 허용 (iptables)
# 실행 서버: WEB1, WEB2, WEB3 각각

# 1. 현재 INPUT 방화벽 규칙 확인
iptables -L INPUT -n -v --line-numbers

# 2. HTTP 80/tcp 허용 규칙이 없는 경우 추가
iptables -C INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || \
iptables -I INPUT 1 -p tcp --dport 80 -j ACCEPT

# 3. HTTP 방화벽 허용 여부 확인
iptables -L INPUT -n -v --line-numbers

# 4. 웹 서버 실행 상태 확인
systemctl is-active nginx

# 5. 웹 서버 자체 HTTP 응답 확인
curl -I http://127.0.0.1

# 6. 로드밸런서(192.168.56.101)에서 확인
# 아래 명령어는 Nginx/HAProxy LB 서버에서 실행
curl -I http://192.168.56.103
curl -I http://192.168.56.104
curl -I http://192.168.56.105

# 정상 결과: HTTP/1.1 200 OK


# 1-4-5. 각 서버가 자신의 번호를 출력하는지 확인
curl -s http://127.0.0.1/ | grep 'WEB SERVER'
curl -I http://127.0.0.1/               # HTTP 200 확인
```

**WEB1, WEB2, WEB3 모두 완료**한 다음 LB 서버에서 `curl -I http://192.168.56.103`, `.104`, `.105`를 실행해 외부 통신을 확인합니다.

## 2. HAProxy + Nginx를 같은 LB VM에 설치

**실행 위치:** `192.168.56.101`

```bash
ssh root@192.168.56.101            # LB 서버 접속
ip -br addr                         # 192.168.56.101 확인
dnf install -y haproxy nginx        # HAProxy와 Nginx 설치
haproxy -v                          # HAProxy 버전 확인
nginx -v                            # Nginx 버전 확인
```


# ============================================================
# 2-1. HAProxy 설치 및 로드밸런싱 설정
# 작업 서버: 192.168.56.101 (HAProxy / Nginx LB)
# ============================================================

# [서버 구성]
# HAProxy : 192.168.56.101:80
# WEB1    : 192.168.56.103:80
# WEB2    : 192.168.56.104:80
# WEB3    : 192.168.56.105:80

# [동작 흐름]
# 클라이언트 → HAProxy Frontend(:80)
#            → ACL 조건 검사
#            → Backend 선택
#            → 로드밸런싱 알고리즘 적용
#            → WEB1 / WEB2 / WEB3
#            → HAProxy를 통해 클라이언트로 응답 반환


# ------------------------------------------------------------
# 1. HAProxy 설치
# ------------------------------------------------------------

# HAProxy 패키지 설치
dnf install -y haproxy

# 설치 버전 확인
haproxy -v


# ------------------------------------------------------------
# 2. 기존 설정 파일 백업
# ------------------------------------------------------------

# 설정 파일이 존재하면 .bak 파일로 백업
# 기존 설정을 복원할 때 사용
[ ! -f /etc/haproxy/haproxy.cfg ] || \
cp -a /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.bak


# ------------------------------------------------------------
# 3. HAProxy 설정 파일 작성
# ------------------------------------------------------------

# cat > : 지정한 파일에 내용을 기록 (기존 내용 덮어쓰기)
# <<'EOF_HAPROXY' : 아래 내용을 종료 표시까지 그대로 입력
# root 권한으로 실행해야 함

cat > /etc/haproxy/haproxy.cfg <<'EOF_HAPROXY'

# ============================================================
# [GLOBAL] HAProxy 전체 프로세스 설정
# ============================================================

global
    # HAProxy 로그를 로컬 syslog로 전달
    # local0는 로그 분류에 사용하는 facility
    log 127.0.0.1 local0

    # HAProxy의 전체 동시 연결 수 제한
    maxconn 4000


# ============================================================
# [DEFAULTS] Frontend/Backend에 공통으로 적용할 기본값
# ============================================================

defaults
    # global에 정의한 로그 설정 사용
    log global

    # HTTP 요청을 처리하는 L7 모드
    mode http

    # HTTP 요청 정보를 포함하는 로그 형식
    option httplog

    # 데이터가 전송되지 않은 연결의 로그 생략
    option dontlognull

    # 백엔드 서버 연결 시도 제한 시간
    timeout connect 5s

    # 클라이언트 측 비활성 연결 타임아웃
    timeout client 30s

    # 백엔드 서버 측 비활성 연결 타임아웃
    timeout server 30s


# ============================================================
# [FRONTEND] 클라이언트 요청을 받는 영역
# ============================================================

frontend web_front

    # HAProxy가 요청을 받을 IP와 TCP 포트
    # 192.168.56.101의 80번 포트에서 HTTP 요청 수신
    bind 192.168.56.101:80

    # --------------------------------------------------------
    # ACL (Access Control List)
    # HTTP 요청 URL의 algo 파라미터를 검사
    #
    # 접속 예시:
    # http://192.168.56.101/?algo=roundrobin
    # http://192.168.56.101/?algo=weighted
    # http://192.168.56.101/?algo=leastconn
    # http://192.168.56.101/?algo=source
    #
    # url_param(algo) : URL에서 algo 파라미터 값 추출
    # -m str          : 문자열 비교
    # --------------------------------------------------------

    # algo=roundrobin이면 algo_rr 조건 충족
    acl algo_rr url_param(algo) -m str roundrobin

    # algo=weighted이면 algo_weighted 조건 충족
    acl algo_weighted url_param(algo) -m str weighted

    # algo=leastconn이면 algo_least 조건 충족
    acl algo_least url_param(algo) -m str leastconn

    # algo=source이면 algo_source 조건 충족
    acl algo_source url_param(algo) -m str source


    # --------------------------------------------------------
    # ACL 조건에 따라 Backend 선택
    # --------------------------------------------------------

    # algo=weighted → 가중치 기반 Backend
    use_backend be_weighted if algo_weighted

    # algo=leastconn → 최소 연결 Backend
    use_backend be_leastconn if algo_least

    # algo=source → 출발지 IP 기반 Backend
    use_backend be_source if algo_source

    # algo=roundrobin → 순차 분산 Backend
    use_backend be_roundrobin if algo_rr

    # URL에 algo가 없거나 조건에 맞지 않으면
    # 기본 Round Robin Backend 사용
    default_backend be_roundrobin


# ============================================================
# [BACKEND 1] Round Robin
# ============================================================

backend be_roundrobin

    # 요청을 WEB1 → WEB2 → WEB3 순서로 분산
    # 서버가 모두 정상이고 가중치가 같다는 조건
    balance roundrobin

    # GET / 요청으로 백엔드의 HTTP 상태 검사
    option httpchk GET /

    # 웹 서버 등록
    # check : 정기적인 상태 검사 활성화
    server web1 192.168.56.103:80 check
    server web2 192.168.56.104:80 check
    server web3 192.168.56.105:80 check


# ============================================================
# [BACKEND 2] Weighted Round Robin
# ============================================================

backend be_weighted

    # Round Robin에 서버별 가중치를 적용
    balance roundrobin

    # HTTP 상태 검사
    option httpchk GET /

    # weight 값으로 요청 분산 비중 설정
    #
    # WEB1 = 5
    # WEB2 = 3
    # WEB3 = 1
    #
    # 총 가중치 = 9
    #
    # 장기적으로 대략 5:3:1 비율로 분산
    # 정확한 요청 순서나 짧은 구간의 횟수는 달라질 수 있음

    server web1 192.168.56.103:80 check weight 5
    server web2 192.168.56.104:80 check weight 3
    server web3 192.168.56.105:80 check weight 1


# ============================================================
# [BACKEND 3] Least Connections
# ============================================================

backend be_leastconn

    # 현재 연결 수가 상대적으로 적은 서버 선택
    # 연결 유지 시간이 길거나 부하가 달라지는 환경에 활용
    balance leastconn

    # HTTP 상태 검사
    option httpchk GET /

    server web1 192.168.56.103:80 check
    server web2 192.168.56.104:80 check
    server web3 192.168.56.105:80 check


# ============================================================
# [BACKEND 4] Source Hash
# ============================================================

backend be_source

    # 클라이언트 출발지 IP를 기반으로 서버 선택
    # 동일 IP는 서버 구성과 상태가 같다면
    # 동일 백엔드로 전달되는 경향이 있음
    balance source

    # HTTP 상태 검사
    option httpchk GET /

    server web1 192.168.56.103:80 check
    server web2 192.168.56.104:80 check
    server web3 192.168.56.105:80 check

    # 주의!
    # NAT에서 MASQUERADE가 적용되면
    # HAProxy가 여러 클라이언트를
    # 동일한 NAT 출발지 IP로 인식할 수 있음


# ============================================================
# [STATS] HAProxy 통계 모니터링 대시보드
# ============================================================

listen stats

    # 9000번 포트로 통계 페이지 제공
    # * 는 서버의 모든 IPv4 인터페이스를 의미
    bind *:9000

    # 통계 페이지 기능 활성화
    stats enable

    # / 경로로 접속 시 통계 화면 제공
    stats uri /

    # 브라우저에서 5초마다 통계 갱신
    stats refresh 5s

    # 통계 화면에 노드 정보 표시
    stats show-node

    # 통계 페이지 HTTP Basic 인증 설정
    # 아래 비밀번호는 실제 사용할 값으로 변경
    stats auth admin:CHANGE_ME_STRONG_PASSWORD

EOF_HAPROXY


# ------------------------------------------------------------
# 4. HAProxy 설정 문법 검사
# ------------------------------------------------------------

# 설정 파일 문법 및 기본 구성 검증
haproxy -c -f /etc/haproxy/haproxy.cfg

# 정상 예시:
# Configuration file is valid


# ------------------------------------------------------------
# 5. HAProxy 실행 및 자동 시작
# ------------------------------------------------------------

# HAProxy 실행 및 부팅 시 자동 실행
systemctl enable --now haproxy

# 기존 실행 중인 HAProxy의 설정을 수정한 경우
# 문법 검사 후 재시작하거나 reload 적용 필요
systemctl reload haproxy


# ------------------------------------------------------------
# 6. 서비스 상태 확인
# ------------------------------------------------------------

# active면 정상 실행 중
systemctl is-active haproxy

# 자세한 상태 확인
systemctl status haproxy


# ------------------------------------------------------------
# 7. HAProxy 포트 확인
# ------------------------------------------------------------

# 80   : 로드밸런서
# 9000 : 통계 페이지
ss -nltp | grep -E ':80|:9000'


# ------------------------------------------------------------
# 8. WEB 서버 정상 연결 확인
# ------------------------------------------------------------

# WEB1
curl -I http://192.168.56.103

# WEB2
curl -I http://192.168.56.104

# WEB3
curl -I http://192.168.56.105

# 모두 HTTP 200 OK가 나오는지 확인


# ------------------------------------------------------------
# 9. HAProxy 알고리즘별 테스트
# ------------------------------------------------------------

# Round Robin
curl 'http://192.168.56.101/?algo=roundrobin'

# Weighted Round Robin
curl 'http://192.168.56.101/?algo=weighted'

# Least Connections
curl 'http://192.168.56.101/?algo=leastconn'

# Source Hash
curl 'http://192.168.56.101/?algo=source'


# ------------------------------------------------------------
# 10. HAProxy 통계 페이지 접속
# ------------------------------------------------------------

# 브라우저에서 접속
# http://192.168.56.101:9000/
#
# 설정한 관리자 계정으로 로그인
# WEB1, WEB2, WEB3 상태 및 연결 통계 확인
#
# 다른 PC에서 접속하려면 9000/tcp 방화벽 허용 필요

### 2-2. Nginx 기본 설정 (`/etc/nginx/nginx.conf`)

**목적:** HAProxy가 80 포트를 사용하므로 Nginx 기본 서버는 `127.0.0.1:8081`, 로드밸런서는 `192.168.56.101:8080` 사용.

```bash
# 원본 백업
cp -a /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak

# 기본 nginx.conf의 server 블록에서 아래 두 listen 줄 변경
vi /etc/nginx/nginx.conf

# 기존 (해당 줄을 찾기)
# listen 80;
# listen [::]:80;

# 변경
# listen 127.0.0.1:8081;
# #listen [::]:80;

# 변경 내용 확인
grep -n 'listen' /etc/nginx/nginx.conf
```

### 2-3. Nginx 로드밸런싱 설정 (`/etc/nginx/conf.d/loadbalancer.conf`)

```bash
cat > /etc/nginx/conf.d/loadbalancer.conf <<'EOF_NGINX'
# URL의 algo 파라미터에 따라 사용할 upstream 결정
map $arg_algo $selected_backend {
    default     web_roundrobin;
    roundrobin  web_roundrobin;
    weighted    web_weighted;
    leastconn   web_leastconn;
    source      web_source;
}

# ① Round Robin
upstream web_roundrobin {
    server 192.168.56.103:80;
    server 192.168.56.104:80;
    server 192.168.56.105:80;
}

# ② Weighted Round Robin (5:3:1)
upstream web_weighted {
    server 192.168.56.103:80 weight=5;
    server 192.168.56.104:80 weight=3;
    server 192.168.56.105:80 weight=1;
}

# ③ Least Connections
upstream web_leastconn {
    least_conn;
    server 192.168.56.103:80;
    server 192.168.56.104:80;
    server 192.168.56.105:80;
}

# ④ Source IP Hash (HAProxy source와 구현은 다름)
upstream web_source {
    ip_hash;
    server 192.168.56.103:80;
    server 192.168.56.104:80;
    server 192.168.56.105:80;
}

# ⑤ Nginx LB
server {
    listen 192.168.56.101:8080;
    server_name _;

    location / {
        proxy_pass http://$selected_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # 테스트용 응답 헤더
        add_header X-LB-Algorithm $selected_backend always;
        add_header X-LB-Upstream $upstream_addr always;
    }
}
EOF_NGINX

# SELinux 상태 확인
getenforce

# 8081 포트가 http_port_t로 등록되어 있는지 확인
semanage port -l | grep http_port_t
# 8081이 없으면 추가 (semanage 명령어가 없다면 policycoreutils-python-utils 설치)
# dnf install -y policycoreutils-python-utils
# semanage port -a -t http_port_t -p tcp 8081

# 이전 실습에서 Nginx의 백엔드 연결이 SELinux로 차단되어 해결한 설정
getsebool httpd_can_network_connect
# 백엔드 연결 시 Permission denied가 나오고 값이 off인 경우 실행
setsebool -P httpd_can_network_connect on


# ==================================================
# Nginx LB 서버 HTTP 8080 포트 허용 (iptables)
# 실행 위치: HAProxy + Nginx 서버 (192.168.56.101)
# ==================================================

# 1. firewalld 실행 상태 확인
systemctl is-active firewalld

# 2. 현재 INPUT 방화벽 규칙 확인
iptables -L INPUT -n -v --line-numbers

# 3. Nginx LB의 8080/tcp 포트 허용
# 동일한 허용 규칙이 없는 경우에만 추가
iptables -C INPUT -p tcp --dport 8080 -j ACCEPT 2>/dev/null || \
iptables -I INPUT 1 -p tcp --dport 8080 -j ACCEPT

# 4. 추가된 방화벽 규칙 확인
iptables -L INPUT -n -v --line-numbers

# 5. Nginx가 8080 포트에서 대기 중인지 확인
ss -nltp | grep ':8080'

# 6. HTTP 응답 확인
curl -I http://192.168.56.101:8080

# 정상 결과: HTTP/1.1 200 OK


# 설정 검사·실행
nginx -t
systemctl enable --now nginx
systemctl is-active nginx
ss -nltp | grep -E ':80|:8080|:8081|:9000'

# WEB1~3 직접 확인
curl -I http://192.168.56.103
curl -I http://192.168.56.104
curl -I http://192.168.56.105

# Nginx LB 응답 확인
curl -I http://192.168.56.101:8080/
```

**주의:** 위 Nginx 설정의 `map`, `upstream`, `server` 블록은 `/etc/nginx/conf.d/loadbalancer.conf`에 들어갑니다. 이 경로는 기본 `nginx.conf`의 `http { include /etc/nginx/conf.d/*.conf; }` 안에서 포함되므로 별도의 `http {}`를 중첩하면 안 됩니다.

## 3. NAT 서버 구성

**실행 위치:** NAT VM (`192.168.0.235`). LB·WEB 서버 설치가 끝난 다음 진행합니다.

```bash
# 3-1. 서버·인터페이스·경로 확인
ip -br addr                       # 외부 192.168.0.235와 내부 인터페이스 확인
ip route                          # 내부망 192.168.56.0/24 경로 확인

# 3-2. IP 포워딩 설정 (재부팅 뒤에도 유지)
cat > /etc/sysctl.d/99-nat-forward.conf <<'EOF_SYSCTL'
net.ipv4.ip_forward = 1
EOF_SYSCTL
sysctl --system                   # 설정 적용
sysctl net.ipv4.ip_forward       # 1 확인

# 3-3. LB 통신 확인
curl -I http://192.168.56.101:80
curl -I http://192.168.56.101:8080
```

### 3-4. NAT 포트포워딩 스크립트 생성

**원본의 `PREROUTING DNAT → FORWARD 허용 → POSTROUTING MASQUERADE` 구조를 유지**했습니다. 기존 규칙을 중복 생성하지 않도록 존재 여부 확인을 추가했습니다. 실행 전 `enp0s8`이 내부망 인터페이스인지 확인하세요.

```bash
cat > /root/nat-conf.sh <<'EOF_NAT'
#!/bin/bash
set -euo pipefail

read -rp '출발지(NAT 외부 IP) 주소: ' src
read -rp '목적지(LB 내부 IP) 주소: ' drc
read -rp '허용할 TCP 포트 번호: ' port

# 기본 입력 확인
[[ "$src" =~ ^[0-9.]+$ && "$drc" =~ ^[0-9.]+$ ]] || { echo 'IP 형식을 확인하세요'; exit 1; }
[[ "$port" =~ ^[0-9]+$ ]] && ((10#$port >= 1 && 10#$port <= 65535)) || { echo '포트 번호를 확인하세요'; exit 1; }

# 1. 외부 IP:port → 내부 LB:port로 DNAT
iptables -t nat -C PREROUTING -d "$src" -p tcp --dport "$port" -j DNAT --to-destination "$drc:$port" 2>/dev/null || 
iptables -t nat -A PREROUTING -d "$src" -p tcp --dport "$port" -j DNAT --to-destination "$drc:$port"

# 2. 포워딩 허용 (외부 → LB)
iptables -C FORWARD -p tcp -d "$drc" --dport "$port" -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || 
iptables -I FORWARD 1 -p tcp -d "$drc" --dport "$port" -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT

# 3. 포워딩 응답 허용 (LB → 외부)
iptables -C FORWARD -p tcp -s "$drc" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || 
iptables -I FORWARD 1 -p tcp -s "$drc" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# 4. 내부망(enp0s8)으로 나가는 트래픽의 출발지 IP 변환
iptables -t nat -C POSTROUTING -o enp0s8 -d "$drc" -p tcp --dport "$port" -j MASQUERADE 2>/dev/null || 
iptables -t nat -A POSTROUTING -o enp0s8 -d "$drc" -p tcp --dport "$port" -j MASQUERADE

# 5. 확인
iptables -t nat -L -n -v --line-numbers
iptables -L FORWARD -n -v --line-numbers
EOF_NAT

chmod 700 /root/nat-conf.sh     # 실행 권한 부여
```

### 3-5. 스크립트를 포트별로 두 번 실행

```bash
# 첫 번째 실행: HAProxy 80 포트 등록
/root/nat-conf.sh
# 출발지(NAT 외부 IP): 192.168.0.235
# 목적지(LB 내부 IP): 192.168.56.101
# 포트 번호: 80

# 두 번째 실행: Nginx 8080 포트 등록
/root/nat-conf.sh
# 출발지(NAT 외부 IP): 192.168.0.235
# 목적지(LB 내부 IP): 192.168.56.101
# 포트 번호: 8080

# 최종 확인
iptables -t nat -L -n -v --line-numbers
iptables -L FORWARD -n -v --line-numbers
```

> **NAT 관련 주의:** 이 스크립트는 **iptables 규칙을 실행 중인 커널에 적용**합니다. 재부팅 후 규칙을 유지하려면 사용하는 방화벽 관리 방식(`firewalld`/`iptables-services` 등)에 맞는 저장 절차를 별도 구성해야 합니다. 특히 `firewalld`와 직접 추가한 iptables 규칙이 함께 동작하면 reload나 재시작 후 규칙이 달라질 수 있으므로 NAT 서버에서는 방화벽 관리 방식을 통일하세요. 또한 외부 PC에서 접근 가능한 외부망은 실습의 `192.168.0.0/24` 로컬 네트워크이며, `192.168.0.235`는 인터넷 공인 IP가 아닙니다.

## 4. 최종 테스트

### 4-1. 내부망 HTTP 상태 검사 (LB VM)

```bash
# WEB1, WEB2, WEB3가 모두 200을 반환해야 함
for ip in 103 104 105; do
    echo -n "WEB ${ip}: "
    curl -sS --max-time 5 -o /dev/null -w '%{http_code}\n' "http://192.168.56.${ip}:80/"
done

# 서비스 확인
systemctl is-active haproxy
systemctl is-active nginx
```

### 4-2. HAProxy 알고리즘별 테스트 (LB VM)

```bash
# 기본 알고리즘: Round Robin
for i in {1..9}; do
  curl -s 'http://192.168.56.101:80/?algo=roundrobin' | grep -o 'WEB SERVER [123] · WEB-0[123]' | head -1
done

# Weighted Round Robin (weight 5:3:1)
for i in {1..90}; do
  curl -s 'http://192.168.56.101:80/?algo=weighted' | grep -o 'WEB SERVER [123] · WEB-0[123]' | head -1
done | sort | uniq -c

# Least Connections
for i in {1..9}; do
  curl -s 'http://192.168.56.101:80/?algo=leastconn' | grep -o 'WEB SERVER [123] · WEB-0[123]' | head -1
done

# Source Hash: 동일한 출발지 IP는 같은 서버로 갈 수 있음
for i in {1..9}; do
  curl -s 'http://192.168.56.101:80/?algo=source' | grep -o 'WEB SERVER [123] · WEB-0[123]' | head -1
done
```

### 4-3. Nginx 알고리즘별 테스트 (LB VM)

```bash
# 응답 헤더에 선택한 알고리즘과 실제 upstream IP 출력
curl -s -D - -o /dev/null 'http://192.168.56.101:8080/?algo=roundrobin' | grep -i '^X-LB-'
curl -s -D - -o /dev/null 'http://192.168.56.101:8080/?algo=weighted'   | grep -i '^X-LB-'
curl -s -D - -o /dev/null 'http://192.168.56.101:8080/?algo=leastconn'  | grep -i '^X-LB-'
curl -s -D - -o /dev/null 'http://192.168.56.101:8080/?algo=source'     | grep -i '^X-LB-'

# Weighted 분산 카운트 (반복 테스트 결과는 연결/요청 상황에 따라 달라질 수 있음)
for i in {1..90}; do
  curl -s -D - -o /dev/null 'http://192.168.56.101:8080/?algo=weighted' | grep -i '^X-LB-Upstream:'
done | sort | uniq -c
```

**알고리즘 참고:** `leastconn`/`least_conn`은 현재 연결 수를 기준으로 동작하므로, `curl`을 직렬로 빠르게 보내는 테스트는 차이를 잘 보여주지 못할 수 있습니다. HAProxy의 `balance source`와 Nginx의 `ip_hash`는 유사한 목적이지만 동일한 해시 알고리즘은 아닙니다.

### 4-4. 외부 PC에서 브라우저 테스트

```text
# 웹브라우저 주소창 (NAT 포워딩 정상 작동 후)
http://192.168.0.235:80/?algo=roundrobin  # HAProxy
http://192.168.0.235:80/?algo=weighted    # HAProxy weighted
http://192.168.0.235:8080/?algo=roundrobin # Nginx
http://192.168.0.235:8080/?algo=weighted   # Nginx weighted
http://192.168.0.235:8080/?algo=leastconn  # Nginx leastconn
http://192.168.0.235:8080/?algo=source     # Nginx source
```

### 4-5. 장애 및 복구 테스트 (실습 환경에서만)

```bash
# WEB3에서 실행: WEB 서비스 중지
ssh root@192.168.56.105
systemctl stop nginx
exit

# LB에서 실행: 정상 WEB 서버로 요청이 처리되는지 확인
for i in {1..9}; do
  curl -sS --max-time 3 'http://192.168.56.101:80/?algo=roundrobin' | grep -o 'WEB SERVER [123] · WEB-0[123]' | head -1
done

# WEB3 다시 시작
ssh root@192.168.56.105
systemctl start nginx
curl -I http://127.0.0.1
exit
```

## 5. 오류 해결 명령어

```bash
# LB 서버: HAProxy 설정 문법 확인
haproxy -c -f /etc/haproxy/haproxy.cfg

# LB 서버: Nginx 설정 문법 확인
nginx -t

# LB 서버: Nginx 502 등 오류 로그 확인
tail -n 50 /var/log/nginx/error.log

# LB 서버: SELinux 상태 확인
getenforce
getsebool httpd_can_network_connect

# LB 서버: WEB3 직접 연결 확인
curl -v --max-time 5 http://192.168.56.105:80/

# WEB3 서버: 서비스/방화벽 확인
systemctl status nginx --no-pager
firewall-cmd --list-services

# NAT 서버: 포워딩 및 변환 규칙 확인
sysctl net.ipv4.ip_forward
iptables -t nat -L -n -v --line-numbers
iptables -L FORWARD -n -v --line-numbers
```

## 6. 작업 완료 체크리스트

- [ ] WEB1~3에서 `curl -I http://127.0.0.1/` → 200 OK
- [ ] WEB1~3의 HTML에 각기 다른 번호 표시
- [ ] 각 WEB 서버에서 HTTP(80/tcp) 방화벽 허용
- [ ] HAProxy `haproxy -c` 검사 통과 및 80번 리스닝
- [ ] Nginx `nginx -t` 검사 통과 및 8080번 리스닝
- [ ] HAProxy 4개 알고리즘의 백엔드 IP가 `192.168.56.103~105`로 통일됨
- [ ] NAT `ip_forward=1`, 80/8080 DNAT, POSTROUTING, FORWARD 확인
- [ ] 외부 PC에서 NAT 80(HAProxy), NAT 8080(Nginx) 접속
- [ ] 장애 테스트 이후 WEB3 서비스 복구

