#!/usr/bin/env bash

##################### VARIÁVEIS PARA O SCRIPT ############################
PROJECT_NAME=${1:-data-engineering}

POSTGRES_VERSION=15
POSTGRES_USER=airflow
POSTGRES_PASSWORD=airflow
POSTGRES_DB=airflow

AIRFLOW_IMAGE=apache/airflow:2.10.5-python3.11
AIRFLOW_UID=1000
AIRFLOW_GID=0
AIRFLOW__CORE__EXECUTOR=LocalExecutor
AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=postgresql+psycopg2://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}
AIRFLOW__CORE__LOAD_EXAMPLES=False
AIRFLOW__CORE__DAGS_ARE_PAUSED_AT_CREATION=True
AIRFLOW__SCHEDULER__SCHEDULER_HEARTBEAT_SEC=5
AIRFLOW__WEBSERVER__WORKERS=2
TEMPORARY_FERNET_KEY="temporary_key_placeholder"

SPARK_IMAGE=bitnami/spark:3.5.5
SPARK_VERSION=3.5.5
SPARK_WORKER_MEMORY=2g
SPARK_DRIVER_MEMORY=1g
SPARK_EXECUTOR_MEMORY=1g

HADOOP_VERSION=3

MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=minioadmin
MINIO_REGION=us-east-1
BUCKETS_LIST="bronze silver gold"

STREAMLIT_PORT=8501


##########################################################################

echo "🛠️ Criando projeto $PROJECT_NAME..."

##############################  PASTAS  ##################################
# Cria estrutura completa de pastas
mkdir -p \
  $PROJECT_NAME/airflow/dags \
  $PROJECT_NAME/airflow/logs \
  $PROJECT_NAME/airflow/plugins \
  $PROJECT_NAME/airflow/config \
  $PROJECT_NAME/spark/conf \
  $PROJECT_NAME/spark/logs \
  $PROJECT_NAME/spark/jars \
  $PROJECT_NAME/minio/config \
  $PROJECT_NAME/minio/data \
  $PROJECT_NAME/postgres/data \
  $PROJECT_NAME/postgres/backups \
  $PROJECT_NAME/monitoring/prometheus \
  $PROJECT_NAME/monitoring/grafana/provisioning/dashboards \
  $PROJECT_NAME/reports/streamlit \
  $PROJECT_NAME/reports/powerbi \
  $PROJECT_NAME/scripts/init \
  $PROJECT_NAME/scripts/sample_data

###################### ROOT ############################################

# Cria arquivo .env com todas variáveis necessárias
cat > $PROJECT_NAME/.env <<EOL
# ===== CORE SETTINGS =====
COMPOSE_PROJECT_NAME=$PROJECT_NAME

# ===== POSTGRESQL =====
POSTGRES_VERSION=$POSTGRES_VERSION
POSTGRES_USER=$POSTGRES_USER
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
POSTGRES_DB=$POSTGRES_DB

# ===== MINIO =====
MINIO_ROOT_USER=$MINIO_ROOT_USER
MINIO_ROOT_PASSWORD=$MINIO_ROOT_PASSWORD
MINIO_REGION=$MINIO_REGION

# ===== AIRFLOW =====
AIRFLOW_IMAGE=$AIRFLOW_IMAGE
AIRFLOW_UID=$AIRFLOW_UID
AIRFLOW_GID=$AIRFLOW_GID
AIRFLOW__CORE__EXECUTOR=$AIRFLOW__CORE__EXECUTOR
AIRFLOW__CORE__FERNET_KEY=$TEMPORARY_FERNET_KEY
AIRFLOW__DATABASE__SQL_ALCHEMY_CONN=$AIRFLOW__DATABASE__SQL_ALCHEMY_CONN

# ===== SPARK =====
SPARK_VERSION=$SPARK_VERSION
HADOOP_VERSION=$HADOOP_VERSION

# ===== STREAMLIT =====
STREAMLIT_PORT=$STREAMLIT_PORT
EOL

echo "✅ .ENV criado com sucesso"

# Cria compose.yaml default
cat > $PROJECT_NAME/compose.yaml <<'EOL'
services:
  postgres:
    image: postgres:${POSTGRES_VERSION}
    env_file: .env
    environment:
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB}
    volumes:
      - ./postgres/data:/var/lib/postgresql/data
      - ./postgres/backups:/backups
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER}"]
      interval: 5s
      timeout: 5s
      retries: 5
    networks:
      - data-net

  minio:
    image: minio/minio
    hostname: minio
    env_file: .env
    environment:
      MINIO_ROOT_USER: ${MINIO_ROOT_USER}
      MINIO_ROOT_PASSWORD: ${MINIO_ROOT_PASSWORD}
    command: server --console-address ":9001" /data
    volumes:
      - ./minio/data:/data
    ports:
      - "9000:9000"
      - "9001:9001"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9000/minio/health/live"]
      interval: 30s
      timeout: 20s
      retries: 3
    networks:
      - data-net

  airflow-webserver:
    build: ./airflow
    env_file: .env
    environment:
      AIRFLOW__DATABASE__SQL_ALCHEMY_CONN: ${AIRFLOW__DATABASE__SQL_ALCHEMY_CONN}
      AIRFLOW__CORE__FERNET_KEY: ${AIRFLOW__CORE__FERNET_KEY}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    user: "${AIRFLOW_UID}:0"  # Garante que o usuário tenha permissão no container
    volumes:
      - ./airflow/dags:/opt/airflow/dags
      - ./airflow/plugins:/opt/airflow/plugins
      - ./airflow/logs:/opt/airflow/logs:z
      - ./airflow/config:/opt/airflow/config
    ports:
      - "8080:8080"
    depends_on:
      postgres:
        condition: service_healthy
      minio:
        condition: service_healthy
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:8080/health || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
    networks:
      - data-net

  spark-master:
    build: ./spark
    env_file: .env
    environment:
      SPARK_MODE: master
      SPARK_MASTER_HOST: spark-master
    volumes:
      - ./spark/conf:/opt/bitnami/spark/conf
    ports:
      - "8081:8080"  # UI do Spark
      - "7077:7077"  # Porta do cluster
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080"]
      interval: 10s
      timeout: 5s
      retries: 3
    networks:
      - data-net

  spark-worker:
    build: ./spark  # Mesma imagem do master
    env_file: .env
    environment:
      SPARK_MODE: worker
      SPARK_MASTER_URL: spark://spark-master:7077
    depends_on:
      - spark-master
    volumes:
      - ./spark/conf:/opt/bitnami/spark/conf
    networks:
      - data-net

  prometheus:
    image: prom/prometheus
    volumes:
      - ./monitoring/prometheus:/etc/prometheus
    ports:
      - "9090:9090"
    networks:
      - data-net

  grafana:
    image: grafana/grafana
    volumes:
      - ./monitoring/grafana:/var/lib/grafana
      - ./monitoring/grafana/provisioning:/etc/grafana/provisioning
    ports:
      - "3000:3000"
    depends_on:
      - prometheus
    restart: unless-stopped
    user: "472:472"  # Usuário específico do Grafana
    healthcheck:
      test: ["CMD-SHELL", "wget --no-verbose --tries=1 --spider http://localhost:3000/api/health || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
    networks:
      - data-net

  streamlit:
    build: ./reports/streamlit
    volumes:
      - ./reports/streamlit:/app
    ports:
      - "${STREAMLIT_PORT}:8501"
    restart: unless-stopped
    stdin_open: true  # Mantém STDIN aberto
    tty: true         # Aloca pseudo-TTY
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:8501/_stcore/health || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5
    networks:
      - data-net

networks:
  data-net:
    driver: bridge
    name: ${COMPOSE_PROJECT_NAME}-net
EOL

echo "✅ compose.yaml criado com sucesso"

########################### AIRFLOW #######################################

# cria o dockerfile do airflow
cat > $PROJECT_NAME/airflow/Dockerfile <<EOL
FROM $AIRFLOW_IMAGE

USER root
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        python3-dev \
        libffi-dev \
        openssl \
        && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /scripts && \
    chown -R airflow:root /scripts && \
    chmod -R 775 /scripts

COPY setup_airflow.sh /scripts/
COPY requirements.txt .

RUN chmod +x /scripts/setup_airflow.sh

# Instala dependências como usuário airflow
USER airflow
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir cryptography==44.0.0 && \
    pip install --no-cache-dir -r requirements.txt

CMD ["bash", "/scripts/setup_airflow.sh"]
EOL

echo "✅ Dockerfile - Airflow -  criado com sucesso"


cat > $PROJECT_NAME/airflow/setup_airflow.sh <<EOL
#!/bin/bash
set -e

echo "⚙️ Iniciando configuração do Airflow..."

export AIRFLOW_HOME=/opt/airflow
export PATH="/home/airflow/.local/bin:$PATH"

echo "🔧 Instalando dependências..."
pip install --no-cache-dir cryptography==44.0.0

echo "🔑 Gerando Fernet Key..."
FERNET_KEY=\$(python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())")
export AIRFLOW__CORE__FERNET_KEY=\$FERNET_KEY

echo "🕒 Aguardando PostgreSQL..."
until pg_isready -h postgres -U $POSTGRES_USER -d $POSTGRES_DB -t 1 &>/dev/null; do
  echo "⏳ Tentativa de conexão com PostgreSQL..."
  sleep 5
done
echo "✅ PostgreSQL está disponível"

airflow db migrate

echo "👤 Verificando/Criando usuário admin..."
airflow users create \
  --username $POSTGRES_USER \
  --password $POSTGRES_PASSWORD \
  --firstname Admin \
  --lastname User \
  --role Admin \
  --email admin@example.com 

sleep 3

echo "🚀 Iniciando serviços do Airflow..."
airflow webserver --port 8080 --daemon &
exec airflow scheduler
EOL

echo "✅ Setup_airflow - Airflow -  criado com sucesso"


# cria o requirements.txt do airflow
cat > $PROJECT_NAME/airflow/requirements.txt <<'EOL'
# Core
apache-airflow==2.10.5
psycopg2-binary==2.9.*
python-dotenv==1.1.*
cryptography==44.0.*
minio==7.2.*

# Providers
apache-airflow-providers-apache-spark==5.1.*
apache-airflow-providers-amazon==9.5.*

# Data Processing
pyspark==3.5.*
pandas==2.2.*
pyarrow==19.0.*
boto3==1.37.*
selenium==4.31.*

EOL

echo "✅ Requirements - Airflow -  criado com sucesso"


########################### SPARK #######################################

# Dockerfile
cat > $PROJECT_NAME/spark/Dockerfile <<EOL
FROM $SPARK_IMAGE
# Instala dependências adicionais
USER root
RUN apt-get update && \\
    apt-get install -y curl python3-pip && \\
    rm -rf /var/lib/apt/lists/*

# Configurações para o Spark
ENV SPARK_WORKER_MEMORY=$SPARK_WORKER_MEMORY
ENV SPARK_DRIVER_MEMORY=$SPARK_DRIVER_MEMORY
ENV SPARK_EXECUTOR_MEMORY=$SPARK_EXECUTOR_MEMORY
EOL

########################  PROMETHEUS  ###################################

cat > $PROJECT_NAME/monitoring/prometheus/prometheus.yaml <<'EOL'
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'spark'
    static_configs:
      - targets: ['spark-master:8080']
  
  - job_name: 'airflow'
    static_configs:
      - targets: ['airflow-webserver:8080']
EOL

########################## STREAMLIT ####################################

cat > $PROJECT_NAME/reports/streamlit/Dockerfile <<EOL
FROM python:3.10-slim

WORKDIR /app

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Configuração para evitar reinicializações indesejadas
ENV STREAMLIT_SERVER_ENABLE_STATIC_SERVING=true
ENV STREAMLIT_SERVER_ENABLE_CORS=false
ENV STREAMLIT_SERVER_ENABLE_XSRF_PROTECTION=true

HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
  CMD curl -f http://localhost:8501/_stcore/health || exit 1

CMD ["streamlit", "run", "app.py", "--server.port=8501", "--server.address=0.0.0.0"]
EOL

# Cria requirements.txt básico para o Streamlit
cat > $PROJECT_NAME/reports/streamlit/requirements.txt <<'EOL'
streamlit==1.44.0
pandas==2.2.*
EOL

echo "✅ Dockerfile e requirements - Streamlit - criados com sucesso"

#################### SCRIPTS ########################################

# Cria scripts de inicialização
cat > $PROJECT_NAME/scripts/init/setup_minio.sh <<EOL
#!/bin/bash
echo "⚙️ Configurando MinIO para "${COMPOSE_PROJECT_NAME}"..."

until (mc alias set minio http://minio:9000 ${MINIO_ROOT_USER} ${MINIO_ROOT_PASSWORD}); do
  echo "🕒 Aguardando MinIO iniciar..."
  sleep 2
done

echo "🪣 Criando buckets..."

for bucket in $BUCKETS_LIST; do
  mc mb minio/${bucket} || echo "Bucket ${bucket} já existe"
  mc policy set public minio/${bucket}
done

echo "📤 Upload de dados de exemplo..."
mc cp /scripts/sample_data/sample_data.csv minio/bronze/

echo "✅ MinIO configurado com sucesso!"
EOL

cat > $PROJECT_NAME/start_project.sh <<EOL
#!/bin/bash

echo "🚀 Iniciando projeto $PROJECT_NAME..."

# Verificar se o Docker está rodando
if ! docker info > /dev/null 2>&1; then
    echo "❌ O Docker não está rodando. Por favor, inicie o Docker primeiro."
    exit 1
fi

# Construir e iniciar os containers
docker compose up -d --build

echo -e "\n⏳ Aguardando inicialização dos serviços (30 segundos)..."
sleep 30 

# Verificar status
echo -e "\n\n🔍 Status dos serviços:"
docker compose ps

# Mostrar URLs de acesso
echo -e "\n🔗 URLs de Acesso:"
echo "- Airflow: http://localhost:8080 ($POSTGRES_USER:$POSTGRES_PASSWORD)"
echo "- MinIO: http://localhost:9001 ($MINIO_ROOT_USER:$MINIO_ROOT_PASSWORD)"
echo "- Spark UI: http://localhost:8081"
echo "- Grafana: http://localhost:3000 (admin:admin)"
echo "- Streamlit: http://localhost:8501"

echo -e "\n✅ Use './check_services.sh' para verificar o status dos serviços"
echo -e "📝 Use 'docker compose logs -f' para ver os logs em tempo real"
EOL


cat > $PROJECT_NAME/stop_project.sh <<EOL
#!/bin/bash

echo "🛑 Parando projeto $PROJECT_NAME..."

docker compose down

echo "✅ Projeto parado. Use './start_project.sh' para reiniciar."
EOL


cat > $PROJECT_NAME/check_services.sh <<'EOL'
#!/bin/bash

services=("postgres" "minio" "airflow-webserver" "spark-master" "grafana" "streamlit")

for service in "${services[@]}"; do
  container_id=$(docker ps -qf "name=${PROJECT_NAME}-${service}-1")
  
  if [ -z "$container_id" ]; then
    echo "⚠️ Container $service não está em execução. Reiniciando..."
    docker compose up -d $service
    sleep 10
  else
    echo "✅ $service está rodando (ID: $container_id)"
  fi
done
EOL


########################## PERMISSÕES DAS PASTAS ##########################################

# Configura permissões
chmod +x $PROJECT_NAME/start_project.sh
chmod +x $PROJECT_NAME/stop_project.sh
chmod +x $PROJECT_NAME/check_services.sh
find "$PROJECT_NAME/scripts/init" -name "*.sh" -exec chmod +x {} \;




################################# PLACEHOLDERS ############################################

# Cria arquivo de dados de exemplo para teste do bucket
echo "id,name,value" > "$PROJECT_NAME/scripts/sample_data/sample_data.csv"
echo "1,test,100" >> "$PROJECT_NAME/scripts/sample_data/sample_data.csv"
echo "2,data,200" >> "$PROJECT_NAME/scripts/sample_data/sample_data.csv"

# 
cat > $PROJECT_NAME/reports/streamlit/app.py <<'EOL'
import streamlit as st

st.write("Arquivo de exemplo do container streamlit")

EOL


############################## MENSAGEM FINAL ###############################################

cat <<EOF
✅ Configurações concluídas com sucesso em $PROJECT_NAME:
   - Estrutura de pastas completa
   - Arquivos de configuração (.env, compose.yaml)
   - Scripts de inicialização
   - Dados de exemplo

🎉 Ambiente pronto para uso!

Para iniciar:
1. cd $PROJECT_NAME
2. sh start_project.sh
EOF