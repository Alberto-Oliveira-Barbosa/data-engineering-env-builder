#!/usr/bin/env bash

##################### VARIÁVEIS PARA O SCRIPT ############################
PROJECT_NAME=${1:-data-engineering}
BUCKETS_LIST="bronze silver gold warehouse temp checkpoints"

echo "🛠️ Criando projeto $PROJECT_NAME..."

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

# Esta será substituída quando o container Airflow for construído
TEMPORARY_FERNET_KEY="temporary_key_until_build_"$(date +%s | sha256sum | base64 | head -c 32)

# Cria arquivo .env com todas variáveis necessárias
cat > $PROJECT_NAME/.env <<EOL
# ===== CORE SETTINGS =====
COMPOSE_PROJECT_NAME=$PROJECT_NAME

# ===== POSTGRESQL =====
POSTGRES_VERSION=13
POSTGRES_USER=airflow
POSTGRES_PASSWORD=airflow
POSTGRES_DB=airflow

# ===== MINIO =====
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=minioadmin
MINIO_REGION=us-east-1

# ===== AIRFLOW =====
AIRFLOW_IMAGE=apache/airflow:2.5.1-python3.8
AIRFLOW_UID=1000
AIRFLOW_GID=0
AIRFLOW__CORE__EXECUTOR=LocalExecutor
AIRFLOW__CORE__FERNET_KEY=$TEMPORARY_FERNET_KEY
AIRFLOW__CORE__SQL_ALCHEMY_CONN=postgresql+psycopg2://\${POSTGRES_USER}:\${POSTGRES_PASSWORD}@postgres:5432/\${POSTGRES_DB}

# ===== SPARK =====
SPARK_VERSION=3.3.0
HADOOP_VERSION=3

# ===== STREAMLIT =====
STREAMLIT_PORT=8501
EOL

echo "✅ .ENV criado com sucesso"

# Cria docker compose.yaml completo
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
      - ./scripts:/scripts
    ports:
      - "9000:9000"
      - "9001:9001"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:9000/minio/health/live"]
      interval: 30s
      timeout: 20s
      retries: 3

  airflow-webserver:
    build: ./airflow
    env_file: .env
    environment:
      AIRFLOW__CORE__SQL_ALCHEMY_CONN: ${AIRFLOW__CORE__SQL_ALCHEMY_CONN}
      AIRFLOW__CORE__FERNET_KEY: ${AIRFLOW__CORE__FERNET_KEY}
    volumes:
      - ./airflow/dags:/opt/airflow/dags
      - ./airflow/plugins:/opt/airflow/plugins
      - ./airflow/logs:/opt/airflow/logs
      - ./airflow/config:/opt/airflow/config
      - ./scripts:/scripts
    ports:
      - "8080:8080"
    depends_on:
      postgres:
        condition: service_healthy
      minio:
        condition: service_healthy

  spark-master:
    build: ./spark
    env_file: .env
    environment:
      SPARK_MODE: master
    volumes:
      - ./spark/conf:/opt/bitnami/spark/conf
      - ./scripts:/scripts
    ports:
      - "8081:8080"
      - "7077:7077"
      - "4040:4040"

  prometheus:
    image: prom/prometheus
    volumes:
      - ./monitoring/prometheus:/etc/prometheus
    ports:
      - "9090:9090"

  grafana:
    image: grafana/grafana
    volumes:
      - ./monitoring/grafana:/var/lib/grafana
      - ./monitoring/grafana/provisioning:/etc/grafana/provisioning
    ports:
      - "3000:3000"
    depends_on:
      - prometheus

  streamlit:
    build: ./reports/streamlit
    volumes:
      - ./reports/streamlit:/app
      - ./scripts:/scripts
    ports:
      - "${STREAMLIT_PORT}:8501"
EOL

echo "✅ compose.yaml criado com sucesso"

# cria o dockerfile do airflow
cat > $PROJECT_NAME/airflow/Dockerfile <<'EOL'
FROM apache/airflow:2.10.5-python3.13

USER root
RUN apt-get update && \
    apt-get install -y openjdk-11-jdk && \
    rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY setup_airflow.sh /scripts/setup_airflow.sh
RUN chmod +x /scripts/setup_airflow.sh

USER airflow
EOL

echo "✅ Dockerfile - Airflow -  criado com sucesso"


cat > $PROJECT_NAME/scripts/init/setup_airflow.sh <<'EOL'
#!/bin/bash
echo "⚙️ Configurando Airflow..."

# Gera chave Fernet definitiva (agora dentro do container com tudo instalado)
FERNET_KEY=$(python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())")
sed -i "s/AIRFLOW__CORE__FERNET_KEY=.*/AIRFLOW__CORE__FERNET_KEY=$FERNET_KEY/" ../.env

# Restante do seu script original...
until (airflow db check); do
  echo "🕒 Aguardando PostgreSQL..."
  sleep 5
done

airflow db init
airflow users create \
  --username ${POSTGRES_USER} \
  --password ${POSTGRES_PASSWORD} \
  --firstname Admin \
  --lastname User \
  --role Admin \
  --email admin@example.com

echo "✅ Airflow configurado com chave Fernet definitiva!"
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
pyspark==3.3.*
pandas==2.2.*
pyarrow==19.0.*
boto3==1.37.*
selenium==4.31.*

# Data Quality
great-expectations==1.3.*
EOL

echo "✅ Requirements - Airflow -  criado com sucesso"

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

# cat > $PROJECT_NAME/scripts/init/setup_airflow.sh <<EOL
# #!/bin/bash
# echo "⚙️ Configurando Airflow para ${PROJECT_NAME}..."

# # Verifica e instala cryptography se necessário
# if ! python3 -c "import cryptography" &> /dev/null; then
#     echo "📦 Instalando pacote cryptography..."
#     pip install cryptography --quiet
# fi

# # Gera e configura a chave Fernet se não existir
# if [ -z "${AIRFLOW__CORE__FERNET_KEY}" ]; then
#     echo "🔑 Gerando chave Fernet..."
#     export AIRFLOW__CORE__FERNET_KEY=$(python3 -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())")
#     echo "AIRFLOW__CORE__FERNET_KEY=${AIRFLOW__CORE__FERNET_KEY}" >> ../.env
# fi

# # Aguarda PostgreSQL ficar disponível
# until (airflow db check); do
#   echo "🕒 Aguardando PostgreSQL..."
#   sleep 5
# done

# # Inicializa o banco de dados
# echo "💾 Inicializando banco de dados..."
# airflow db init

# # Cria usuário admin (se não existir)
# echo "👤 Verificando/Criando usuário admin..."
# if ! airflow users get --username ${POSTGRES_USER} &> /dev/null; then
#     airflow users create \
#         --username ${POSTGRES_USER} \
#         --password ${POSTGRES_PASSWORD} \
#         --firstname Admin \
#         --lastname User \
#         --role Admin \
#         --email admin@example.com
#     echo "✅ Usuário admin criado com sucesso!"
# else
#     echo "ℹ️ Usuário admin já existe"
# fi

# # Configurações adicionais recomendadas
# airflow variables set setup_complete true

# echo "✅ Airflow configurado com sucesso!"

# EOL

# echo "✅ Script airrflow 2  -  criado com sucesso"

# Configura permissões
find "$PROJECT_NAME/scripts/init" -name "*.sh" -exec chmod +x {} \;

# Cria arquivo de dados de exemplo
echo "id,name,value" > "$PROJECT_NAME/scripts/sample_data/sample_data.csv"
echo "1,test,100" >> "$PROJECT_NAME/scripts/sample_data/sample_data.csv"
echo "2,data,200" >> "$PROJECT_NAME/scripts/sample_data/sample_data.csv"

# Mensagem final de sucesso
cat <<EOF

✅ Configurações concluídas com sucesso em '$PROJECT_NAME':
   - Estrutura de pastas completa
   - Arquivos de configuração (.env, compose.yaml)
   - Scripts de inicialização
   - Dados de exemplo

🎉 Ambiente pronto para uso!

Para iniciar:
1. cd ${PROJECT_NAME}
2. docker compose up -d --build

Acessos após inicialização:
• Airflow UI: http://localhost:8080 (admin/airflow)
• MinIO Console: http://localhost:9001 (minioadmin/minioadmin)
• Grafana: http://localhost:3000 (admin/admin)
EOF