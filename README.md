[README.md](https://github.com/user-attachments/files/33861913/README.md)
# NAT + HAProxy + Nginx 로드밸런싱 실습

Rocky Linux · VirtualBox · iptables · HAProxy · Nginx

> **실습 순서:** VM 네트워크 준비 → WEB1·2·3 → HAProxy → Nginx LB → NAT → 전체 테스트. 모든 명령은 별도 표기가 없으면 **root**로 실행합니다. 이 문서는 `192.168.0.0/24`, `192.168.56.0/24`를 사용하는 **교육용 LAN 환경** 기준입니다. 실서비스에 그대로 배포하지 마세요.

## 0. 구성도 및 IP

```text
클라이언트 PC (192.168.0.x)
    │ 웹 브라우저 (80 또는 8080)
    ▼
NAT VM [브리지: 192.168.0.235]
       [Host-Only: 192.168.56.100 (예시)]
    │ DNAT / FORWARD / MASQUERADE
    ├── TCP 80   ──> HAProxy 192.168.56.101:80 ─┐
    └── TCP 8080 ──> Nginx   192.168.56.101:8080 ┤
                                                    │ 두 LB는 같은 VM, 별도 포트
                                ┌───────────────────┴──────────┐
                                ▼               ▼              ▼
                          WEB1 :80         WEB2 :80        WEB3 :80
                       192.168.56.103   192.168.56.104  192.168.56.105
```

| 서버 | 주소 | 주요 역할 |
| --- | --- | --- |
| NAT | 외부 `192.168.0.235`, 내부 `192.168.56.100` **예시** | IP/포트 변환, 패킷 전달 |
| LB VM | `192.168.56.101` | HAProxy `:80`, Nginx `:8080`, 기본 로컬 Nginx `127.0.0.1:8081` |
| WEB1 | `192.168.56.103:80` | 서버 식별 페이지 |
| WEB2 | `192.168.56.104:80` | 서버 식별 페이지 |
| WEB3 | `192.168.56.105:80` | 서버 식별 페이지 |

**사전 준비**

1. VirtualBox VM 5대: NAT, LB, WEB1, WEB2, WEB3. Rocky Linux를 설치합니다.
2. NAT VM: 어댑터 1 = **브리지**, 어댑터 2 = **호스트 전용(Host-Only)**. NAT의 내부 주소 `192.168.56.100/24`는 이 안내를 위해 선택한 **예시 값**이므로 기존에 쓰는 주소가 있으면 유지하세요. 실제 인터페이스 이름도 확인하세요.
3. LB/WEB VM: Host-Only 어댑터를 동일한 가상 네트워크에 연결하고 위 표의 `192.168.56.x/24` 주소를 각각 부여합니다. **VirtualBox의 'NAT' 어댑터 모드와 여기서 구축하는 Linux NAT 서버는 다른 개념**입니다.
4. **패키지 설치용 인터넷 경로와 DNS가 필요**합니다. Host-Only 전용 VM은 기본적으로 인터넷이 되지 않으므로, 설치 중 임시 인터넷 연결을 제공하거나 NAT VM을 기본 게이트웨이로 설정하고 NAT VM에 인터넷 공유 규칙을 추가해야 합니다. 아래 DNAT 실습 스크립트만으로는 일반 인터넷 접속이 제공되지 않습니다.
5. IP 주소 중복을 피하고, 다른 PC에서 `192.168.0.235`로 도달 가능한 같은 LAN인지 확인합니다. 실제 인터페이스가 `enp0s8`이 아니면 NAT 설정을 수정해야 합니다.

### 0-1. 각 VM에서 네트워크 점검

```bash
hostname                         # 현재 VM 이름
ip -br addr                      # 실제 IP와 인터페이스 이름
ip route                         # 라우팅 테이블 확인
ping -c 3 192.168.56.101         # LB 내부 IP에 도달하는지 확인 (WEB에서 실행)
```

> **IP를 처음 설정하는 경우** NetworkManager의 `nmcli connection show` / `nmcli connection modify`를 사용하세요. 연결 프로필과 인터페이스 이름은 PC마다 다르므로 임의로 `enp0s8`을 모든 VM에 복사하지 않습니다. IP가 먼저 구성되어야 아래 SSH와 설치 명령이 성공합니다.

### 0-2. 방화벽 관리 방식 확인 (모든 VM)

```bash
systemctl is-active firewalld     # active면 firewalld 정책도 고려해야 함
iptables -L INPUT -n -v          # INPUT 규칙
iptables -L FORWARD -n -v        # FORWARD 규칙 (특히 NAT VM)
```

**이 가이드는 iptables 명령을 사용한 실습**입니다. Rocky Linux에서 firewalld가 활성화되어 있으면 `iptables -I`만으로 통신이 보장되지 않으며 firewalld 재시작·reload 시 규칙이 달라질 수 있습니다. 관리자와 상의해 한 방식으로 통일하세요. 이미 구동 중인 방화벽을 무작정 중단하지 마세요. 이 문서의 iptables 규칙은 별도 영구 저장 전까지 재부팅 후 소실될 수 있습니다.

---

## 1. WEB1·WEB2·WEB3 구축 (각 VM에서 반복)

### 1-1. 한 서버에 접속하고 설치

```bash
# SSH 접근 가능한 NAT 또는 관리 PC에서, 한 번에 하나씩 접속
ssh root@192.168.56.103       # WEB1; 완료 후 exit
# ssh root@192.168.56.104     # WEB2
# ssh root@192.168.56.105     # WEB3

hostname                       # 접속 서버 확인
ip -br addr                    # 해당 WEB IP 확인
dnf install -y nginx           # 웹 서버 패키지 설치
nginx -v                       # 버전 확인
systemctl enable --now nginx  # 서비스 즉시 실행 + 자동 시작
systemctl is-active nginx     # active여야 함
ss -nltp | grep ':80'         # TCP 80 포트 LISTEN 확인
```

### 1-2. 각 서버별 HTML 페이지 생성

**WEB1에서는 `WEB_NUM=1`, WEB2에서는 `WEB_NUM=2`, WEB3에서는 `WEB_NUM=3`으로 설정**한 후 아래 공통 명령을 실행합니다. 사용자 입력에 따라 HTML 내용만 달라집니다.

```bash
# WEB1 / WEB2 / WEB3 각각 하나만 설정
WEB_NUM=1
# WEB_NUM=2
# WEB_NUM=3

# 번호에 대응하는 서버 주소 자동 생성
WEB_IP="192.168.56.$((102 + WEB_NUM))"
echo "WEB${WEB_NUM} = ${WEB_IP}"   # WEB1=.103, WEB2=.104, WEB3=.105

# 기존 HTML을 백업 (존재할 때만)
if [ -f /usr/share/nginx/html/index.html ]; then
    cp -a /usr/share/nginx/html/index.html /usr/share/nginx/html/index.html.bak
fi

# ${WEB_NUM}과 ${WEB_IP}를 실제 값으로 치환하여 HTML 작성
cat > /usr/share/nginx/html/index.html <<EOF_HTML
<!doctype html>
<html lang="ko">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>HAProxy / Nginx 실습 - WEB SERVER ${WEB_NUM}</title>
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

restorecon -v /usr/share/nginx/html/index.html  # SELinux 파일 문맥 복원
curl -s http://127.0.0.1/ | grep 'WEB SERVER'  # 내 서버 번호 확인
curl -I http://127.0.0.1/                 # HTTP 200 확인 (자기 자신만 확인)
```

### 1-3. WEB HTTP 방화벽 허용 (iptables 방식)

```bash
# 실행 위치: WEB1, WEB2, WEB3 각각
iptables -L INPUT -n -v --line-numbers   # 기존 정책 확인

# LB(192.168.56.101)에서 오는 HTTP 요청만 허용
iptables -C INPUT -s 192.168.56.101 -p tcp --dport 80 -j ACCEPT 2>/dev/null || \
iptables -I INPUT 1 -s 192.168.56.101 -p tcp --dport 80 -j ACCEPT

iptables -L INPUT -n -v --line-numbers   # 허용 규칙 확인

# 주의: 위 ACCEPT만으로 다른 출발지가 차단되는 것은 아님.
# 정책상 필요한 추가 제한은 운영 환경에서 별도로 구성.
```

**3대 완료 후 LB VM(`192.168.56.101`)에서** 다음을 실행해 실제 서버 간 HTTP 연결을 확인합니다. 루프백 성공만으로 외부 접근 가능 여부를 판단하지 마세요.

```bash
curl -I http://192.168.56.103/  # WEB1: HTTP 200
curl -I http://192.168.56.104/  # WEB2: HTTP 200
curl -I http://192.168.56.105/  # WEB3: HTTP 200
```

---

## 2. LB VM에 HAProxy + Nginx 설치

**실행 위치: `192.168.56.101`**

```bash
ssh root@192.168.56.101             # 다른 호스트에서 LB 접속
ip -br addr                          # .101 주소 확인
dnf install -y haproxy nginx        # 패키지 설치
haproxy -v                           # 버전 확인
nginx -v                             # 버전 확인
```

### 2-1. HAProxy 설정 `/etc/haproxy/haproxy.cfg`

```bash
# 기존 설정 백업
if [ -f /etc/haproxy/haproxy.cfg ]; then
    cp -a /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.bak
fi

# 아래 EOF 사이의 HAProxy 텍스트를 설정 파일에 저장
cat > /etc/haproxy/haproxy.cfg <<'EOF_HAPROXY'
global
    log 127.0.0.1 local0            # 로컬 syslog 사용 (rsyslog 연동 필요)
    maxconn 4000                    # 프로세스 동시 연결 상한

defaults
    log global                      # global 로그 설정 상속
    mode http                       # HTTP(L7) 모드
    option httplog                  # HTTP 로그 형식
    option dontlognull              # 데이터 없는 연결 로그 생략
    timeout connect 5s             # 백엔드 연결 대기
    timeout client 30s             # 클라이언트 비활성 타임아웃
    timeout server 30s             # 서버 측 비활성 타임아웃

frontend web_front
    bind 192.168.56.101:80           # 클라이언트 요청 수신 포트
    # ACL: URL의 ?algo= 값이 무엇인지 판별
    acl algo_rr       url_param(algo) -m str roundrobin
    acl algo_weighted url_param(algo) -m str weighted
    acl algo_least    url_param(algo) -m str leastconn
    acl algo_source   url_param(algo) -m str source

    # ACL에 따라 아래의 특정 backend를 선택
    use_backend be_weighted if algo_weighted
    use_backend be_leastconn if algo_least
    use_backend be_source if algo_source
    use_backend be_roundrobin if algo_rr
    default_backend be_roundrobin    # algo 생략 시 기본값

backend be_roundrobin
    balance roundrobin               # 서버 순환 선택
    option httpchk GET /             # HTTP GET / 응답으로 상태 점검
    server web1 192.168.56.103:80 check
    server web2 192.168.56.104:80 check
    server web3 192.168.56.105:80 check

backend be_weighted
    balance roundrobin               # 라운드로빈 + 가중치
    option httpchk GET /
    server web1 192.168.56.103:80 check weight 5
    server web2 192.168.56.104:80 check weight 3
    server web3 192.168.56.105:80 check weight 1

backend be_leastconn
    balance leastconn                # 현재 활성 연결 수 기반
    option httpchk GET /
    server web1 192.168.56.103:80 check
    server web2 192.168.56.104:80 check
    server web3 192.168.56.105:80 check

backend be_source
    balance source                   # 클라이언트 출발지 IP 기반 해시
    option httpchk GET /
    server web1 192.168.56.103:80 check
    server web2 192.168.56.104:80 check
    server web3 192.168.56.105:80 check

# 통계 화면: 반드시 비밀번호를 수정하고 접근 제한
listen stats
    bind *:9000
    stats enable
    stats uri /
    stats refresh 5s
    stats show-node
    stats auth admin:REPLACE_WITH_UNIQUE_PASSWORD
EOF_HAPROXY

# 위 설정은 실제 환경에 맞게 인증 비밀번호를 변경한 후 검사
haproxy -c -f /etc/haproxy/haproxy.cfg  # 문법 검사 통과 확인
systemctl enable --now haproxy         # 실행 및 자동 시작
# 이미 실행 중인 서비스를 수정했다면: systemctl reload haproxy
systemctl is-active haproxy            # active 확인
ss -nltp | grep -E ':80|:9000'         # 수신 포트 확인
```

> `log 127.0.0.1 local0`는 HAProxy가 로그를 전달할 syslog 대상이며, 파일에 실제로 기록하려면 rsyslog 수신/분류 설정이 별도로 필요합니다. 통계 페이지 `9000/tcp`는 관리자 전용으로 접근을 제한하세요.

### 2-2. Nginx 기본 서버 포트 변경 `/etc/nginx/nginx.conf`

HAProxy가 이미 `192.168.56.101:80`을 사용하므로 기본 Nginx가 `*:80`을 점유하지 않도록 수정합니다. **실제 로드밸런서 포트는 `8080`이고, `8081`은 VM 자기 자신용 기본 Nginx 페이지입니다.**

```bash
cp -a /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak  # 기존 원본 백업
vi /etc/nginx/nginx.conf                           # 기본 server 블록 수정

# 기본 server 블록의 원래 내용(찾을 부분):
# listen 80;
# listen [::]:80;

# 실제로 다음과 같이 변경 (주석을 복사하지 말고 편집기 안에서 수정):
# listen 127.0.0.1:8081;
# # listen [::]:80;

# nginx.conf 내 http { ... include /etc/nginx/conf.d/*.conf; ... } 유지
grep -n 'listen' /etc/nginx/nginx.conf                 # 변경 확인
```

### 2-3. Nginx 로드밸런서 설정 `/etc/nginx/conf.d/loadbalancer.conf`

```bash
# map / upstream / server 블록을 nginx.conf의 http 블록에 포함되는 conf.d에 저장
cat > /etc/nginx/conf.d/loadbalancer.conf <<'EOF_NGINX'
# ?algo= 값에 따라 로드밸런싱 서버 그룹 선택
map $arg_algo $selected_backend {
    default     web_roundrobin;
    roundrobin  web_roundrobin;
    weighted    web_weighted;
    leastconn   web_leastconn;
    source      web_source;
}

# ① 기본 Round Robin: 서버 순환
upstream web_roundrobin {
    server 192.168.56.103:80;
    server 192.168.56.104:80;
    server 192.168.56.105:80;
}

# ② Weighted Round Robin: 5:3:1
upstream web_weighted {
    server 192.168.56.103:80 weight=5;
    server 192.168.56.104:80 weight=3;
    server 192.168.56.105:80 weight=1;
}

# ③ Least Connections: 활성 연결 수가 상대적으로 적은 서버
upstream web_leastconn {
    least_conn;
    server 192.168.56.103:80;
    server 192.168.56.104:80;
    server 192.168.56.105:80;
}

# ④ IP Hash: 클라이언트 IP 기반 (HAProxy source와 구현은 다름)
upstream web_source {
    ip_hash;
    server 192.168.56.103:80;
    server 192.168.56.104:80;
    server 192.168.56.105:80;
}

server {
    listen 192.168.56.101:8080;             # 외부 요청을 받는 Nginx LB 포트
    server_name _;

    location / {
        proxy_pass http://$selected_backend; # map에서 선택한 upstream으로 전달
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # 어떤 그룹/백엔드 서버가 선택됐는지 응답 헤더로 확인
        add_header X-LB-Algorithm $selected_backend always;
        add_header X-LB-Upstream $upstream_addr always;
    }
}
EOF_NGINX

# Nginx 설정 파일 문법 확인 (문제가 있으면 아래 단계를 진행하지 않음)
nginx -t
```

### 2-4. SELinux 정책 확인

```bash
getenforce                                      # Enforcing/Permissive/Disabled

# 명령어가 없으면 dnf install -y policycoreutils-python-utils
semanage port -l | grep http_port_t           # Nginx 기본 8081 포트 등록 확인

# 8081/tcp가 http_port_t에 없는 경우에만 실행
# semanage port -a -t http_port_t -p tcp 8081
# 포트가 이미 다른 유형으로 등록되어 있으면 충돌 원인을 먼저 확인

getsebool httpd_can_network_connect           # httpd/Nginx가 백엔드에 연결 가능한지 확인
# 실습에서 Nginx 오류 로그의 '(13: Permission denied)' 및 off 확인 후 조정
# setsebool -P httpd_can_network_connect on
```

> SELinux 설정은 전역 정책에 영향을 줄 수 있으므로 **오류 발생 시 로그와 상태를 확인한 다음 필요한 명령만 실행**합니다. 방화벽 포트 `8080`을 열어도 SELinux의 백엔드 접속 차단은 자동으로 해결되지 않습니다.

### 2-5. LB 서버의 8080 포트 방화벽 허용

```bash
# LB VM에서 실행: INPUT 체인에서 Nginx 8080 요청 수신 허용
iptables -L INPUT -n -v --line-numbers
iptables -C INPUT -p tcp --dport 8080 -j ACCEPT 2>/dev/null || \
iptables -I INPUT 1 -p tcp --dport 8080 -j ACCEPT
iptables -L INPUT -n -v --line-numbers

# HAProxy의 80도 기존 방화벽에서 허용되어 있어야 함.
# stats 9000은 외부에 무조건 열지 말고 관리자 IP만 제한 허용.
```

### 2-6. 서비스 실행 및 접속 확인

```bash
nginx -t                              # 설정 문법 검사
systemctl enable --now nginx         # Nginx 실행 + 자동 시작
systemctl is-active nginx            # active 확인
ss -nltp | grep -E ':80|:8080|:8081|:9000'  # 모든 리스닝 포트 확인

curl -I http://127.0.0.1:8081         # 로컬 기본 Nginx (외부 공개 불필요)
curl -I http://192.168.56.101:80     # HAProxy 80
curl -I http://192.168.56.101:8080   # Nginx LB 8080

# 실패 시 로그 확인
tail -n 50 /var/log/nginx/error.log
```

---

## 3. NAT 서버 포트포워딩

**실행 위치: NAT VM** (`192.168.0.235` 외부 IP, Host-Only 내부 연결). `192.168.0.235`는 사설 IP이며 같은 실습 LAN에서 접속하기 위한 주소입니다.

### 3-1. NIC·라우팅·IP 포워딩 확인

```bash
ip -br addr                              # 브리지·내부 IP/인터페이스 확인
ip route                                 # 라우팅 확인
ip route get 192.168.56.101              # LB로 향하는 실제 인터페이스 확인

# 재부팅 후에도 IPv4 포워딩 유지
cat > /etc/sysctl.d/99-nat-forward.conf <<'EOF_SYSCTL'
net.ipv4.ip_forward = 1
EOF_SYSCTL
sysctl --system                          # 파일 설정 적용
sysctl net.ipv4.ip_forward                # 1 확인

curl -I http://192.168.56.101:80         # NAT → HAProxy 통신
curl -I http://192.168.56.101:8080       # NAT → Nginx 통신
```

### 3-2. 포트 포워딩 스크립트 만들기

기존 실습과 같이 **DNAT → FORWARD → MASQUERADE** 순서이며, 동일한 규칙은 중복 추가하지 않도록 검사합니다. `enp0s8`은 실습 NAT VM의 Host-Only 인터페이스 이름입니다.

```bash
cat > /root/nat-conf.sh <<'EOF_NAT'
#!/bin/bash
set -euo pipefail

read -rp 'NAT 외부(브리지) IP: ' src
read -rp 'LB 내부 IP: ' drc
read -rp '허용할 TCP 포트: ' port

# 학습용 입력 검증 (IPv4 주소는 실제 ip -br addr 결과와 반드시 비교)
[[ "$src" =~ ^[0-9.]+$ && "$drc" =~ ^[0-9.]+$ ]] || { echo 'IP 형식 확인'; exit 1; }
[[ "$port" =~ ^[0-9]+$ ]] && (( 10#$port >= 1 && 10#$port <= 65535 )) || { echo '포트 확인'; exit 1; }

# NAT:port로 들어온 패킷의 목적지 → LB:port (DNAT)
iptables -t nat -C PREROUTING -d "$src" -p tcp --dport "$port" -j DNAT --to-destination "$drc:$port" 2>/dev/null || \
iptables -t nat -A PREROUTING -d "$src" -p tcp --dport "$port" -j DNAT --to-destination "$drc:$port"

# 신규 연결을 내부 LB로 전달할 수 있도록 FORWARD 허용
iptables -C FORWARD -p tcp -d "$drc" --dport "$port" -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || \
iptables -I FORWARD 1 -p tcp -d "$drc" --dport "$port" -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT

# 반환되는 응답 패킷의 FORWARD 허용
iptables -C FORWARD -p tcp -s "$drc" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || \
iptables -I FORWARD 1 -p tcp -s "$drc" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# 내부망으로 나가는 패킷의 출발지 IP를 NAT 내부 IP로 변환 (응답 경로 확보)
# 실제 내부 NIC가 enp0s8인지 'ip route get 192.168.56.101'로 확인
iptables -t nat -C POSTROUTING -o enp0s8 -d "$drc" -p tcp --dport "$port" -j MASQUERADE 2>/dev/null || \
iptables -t nat -A POSTROUTING -o enp0s8 -d "$drc" -p tcp --dport "$port" -j MASQUERADE

# 규칙 목록 및 패킷 카운터 확인
iptables -t nat -L -n -v --line-numbers
iptables -L FORWARD -n -v --line-numbers
EOF_NAT

chmod 700 /root/nat-conf.sh               # root만 실행하도록 권한 설정
bash -n /root/nat-conf.sh                  # 셸 문법 검사
```

### 3-3. 스크립트 두 번 실행

```bash
# HAProxy 외부 80 → 내부 192.168.56.101:80
/root/nat-conf.sh
# 입력 순서: 192.168.0.235 / 192.168.56.101 / 80

# Nginx 외부 8080 → 내부 192.168.56.101:8080
/root/nat-conf.sh
# 입력 순서: 192.168.0.235 / 192.168.56.101 / 8080

iptables -t nat -L -n -v --line-numbers   # DNAT / MASQUERADE 확인
iptables -L FORWARD -n -v --line-numbers # 전달 허용 확인
```

> **NAT 규칙은 실습 중 즉시 적용되지만 영구 저장은 별도**입니다. 방화벽 저장 방식은 firewalld / iptables-services 중 선택한 관리 방식에 맞춰 구성해야 합니다. 위 스크립트는 NAT 로컬 호스트에서 자신의 외부 IP로 접속하는 OUTPUT 트래픽까지 포워딩하지 않습니다. **NAT 테스트는 다른 PC에서 실시**하세요.

---

## 4. 전체 테스트

### 4-1. LB 서버에서 각 WEB 직접 연결

```bash
for ip in 103 104 105; do
    echo -n "WEB${ip} HTTP: "
    curl -sS --max-time 5 -o /dev/null -w '%{http_code}\n' "http://192.168.56.${ip}:80/"
done
# 정상: 모두 200
```

### 4-2. HAProxy 4가지 알고리즘 테스트 (LB VM)

```bash
# URL 파라미터만 바꾸면 서로 다른 backend가 선택됨
for algo in roundrobin weighted leastconn source; do
    echo "===== HAProxy: ${algo} ====="
    for i in {1..9}; do
        curl -s --max-time 5 "http://192.168.56.101:80/?algo=${algo}" \
        | grep -o 'WEB SERVER [123] · WEB-0[123]' | head -1
    done
done

# Weighted 분배 경향 확인 (정확한 5:3:1 횟수는 보장되지 않음)
for i in {1..90}; do
    curl -s 'http://192.168.56.101:80/?algo=weighted' \
    | grep -o 'WEB SERVER [123] · WEB-0[123]' | head -1
done | sort | uniq -c
```

### 4-3. Nginx 4가지 알고리즘 테스트 (LB VM)

```bash
# 헤더에 선택한 그룹 및 실제 대상 서버가 출력됨
for algo in roundrobin weighted leastconn source; do
    echo "===== Nginx: ${algo} ====="
    curl -s -D - -o /dev/null "http://192.168.56.101:8080/?algo=${algo}" | grep -i '^X-LB-'
done

# Weighted 분산 횟수 확인
for i in {1..90}; do
    curl -s -D - -o /dev/null 'http://192.168.56.101:8080/?algo=weighted' \
    | grep -i '^X-LB-Upstream:'
done | sort | uniq -c
```

**알고리즘 참고:** `leastconn`은 동시 연결 상황에서 특징이 드러나므로, 짧은 `curl`을 하나씩 요청하면 Round Robin과 차이가 작을 수 있습니다. `source`/`ip_hash`는 출발지 IP 기반이나 구현 알고리즘이 같지는 않습니다. NAT의 MASQUERADE 때문에 서로 다른 PC가 같은 출발지 IP로 보일 수 있습니다.

### 4-4. 외부 PC 브라우저에서 확인

```text
HAProxy 기본:      http://192.168.0.235/?algo=roundrobin
HAProxy Weighted: http://192.168.0.235/?algo=weighted
HAProxy Least:    http://192.168.0.235/?algo=leastconn
HAProxy Source:   http://192.168.0.235/?algo=source

Nginx 기본:       http://192.168.0.235:8080/?algo=roundrobin
Nginx Weighted:  http://192.168.0.235:8080/?algo=weighted
Nginx Least:     http://192.168.0.235:8080/?algo=leastconn
Nginx Source:    http://192.168.0.235:8080/?algo=source
```

### 4-5. 장애 후 복구 (실습 서버에서만 실행)

```bash
# LB VM에서 실행: WEB3의 Nginx 중지
ssh root@192.168.56.105 'systemctl stop nginx'

# LB VM에서 HAProxy Health Check 동작 관찰
for i in {1..9}; do
    curl -sS --max-time 5 'http://192.168.56.101/?algo=roundrobin' \
    | grep -o 'WEB SERVER [123] · WEB-0[123]' | head -1
done

# 중지한 서버 복구 (실습이 끝나면 반드시 실행)
ssh root@192.168.56.105 'systemctl start nginx'
curl -I http://192.168.56.105/
```

---

## 5. 오류 점검

```bash
# LB VM: 서비스/설정
haproxy -c -f /etc/haproxy/haproxy.cfg
nginx -t
systemctl status haproxy --no-pager
systemctl status nginx --no-pager
ss -nltp | grep -E ':80|:8080|:8081|:9000'

# LB VM: Nginx 502 또는 Permission denied
tail -n 50 /var/log/nginx/error.log
getenforce
getsebool httpd_can_network_connect

# WEB VM: 포트/방화벽/HTML
systemctl status nginx --no-pager
iptables -L INPUT -n -v --line-numbers
curl -I http://127.0.0.1/

# NAT VM: 주소/라우팅/변환/전달
ip -br addr
ip route get 192.168.56.101
sysctl net.ipv4.ip_forward
iptables -t nat -L -n -v --line-numbers
iptables -L FORWARD -n -v --line-numbers
```

## 6. 부하 테스트
sudo dnf install epel-release
sudo dnf install stress stress-ng
stress -c 4 --timeout 60
- [ ] stats 인증 비밀번호 변경, 관리 페이지 접근 제한

**보안/운영 주의:** 이 문서는 로컬 실습용으로 작성되었습니다. 실서비스에서는 암호화(HTTPS), 접근 통제, syslog 구성, 상태 검사, 방화벽 규칙 영구 관리 및 로드밸런서 이중화를 추가로 설계해야 합니다.
