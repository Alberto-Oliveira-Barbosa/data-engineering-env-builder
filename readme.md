# Data Engineering Development Environment Builder

Este projeto oferece um **script de automação** para criar ambientes de desenvolvimento de dados **com um único comando**.   
Ele simplifica a configuração de toda a infraestrutura necessária, incluindo:  
  
- **Configuração automática** de pastas, variáveis de ambiente e redes Docker  
- **Pré-otimizado** para pipelines de dados (ETL/ELT)  
- **Escalável**: desde ambientes locais até deployments em nuvem  
- **Observabilidade integrada** (coleta de métricas + dashboards)  


#### **Por que usar este projeto?**  
- **Padronização**: Todos os desenvolvedores usam a mesma stack configurada  
- **Produtividade**: Elimina horas de setup manual  
- **Flexibilidade**: Adaptável para diferentes casos de uso (batch/streaming)  


#### **Serviços Integrados**  
- **Orquestração**: Apache Airflow (com PostgreSQL)  
- **Processamento**: Apache Spark (cluster standalone)  
- **Armazenamento**: MinIO (S3-compatível)  
- **Monitoramento**: Prometheus + Grafana (métricas em tempo real)  
- **Visualização**: Streamlit (dashboards interativos)  


## Visão Geral da Estrutura Criada:
Este projeto cria um ambiente completo de engenharia de dados com os seguintes componentes:
- **Airflow** (2.10.5): Orquestração de pipelines
- **PostgreSQL** (15): Banco de dados para o Airflow
- **Spark** (3.5.5): Processamento distribuído
- **MinIO**: Armazenamento de objetos compatível com S3
- **Prometheus/Grafana**: Monitoramento
- **Streamlit** (1.44.0): Visualização de dados

### Pré-requisitos
- Docker e Docker Compose instalados
- Linux/macOS (para Windows, use WSL2)

### Estrutura dos Diretórios:
```
nome-do-projeto/
├── airflow/               # Configurações do Airflow
│   ├── dags/              # Diretório para DAGs
│   ├── logs/              # Logs do Airflow
│   ├── plugins/           # Plugins customizados
│   ├── config/            # Arquivos de configuração
│   ├── Dockerfile         # Imagem customizada do Airflow
│   └── requirements.txt   # Dependências Python
├── spark/                 # Configurações do Spark
├── minio/                 # Armazenamento de objetos
├── postgres/              # Dados do PostgreSQL
├── monitoring/            # Prometheus e Grafana
├── reports/               # Dashboards (Streamlit/PowerBI)
└── scripts/               # Scripts auxiliares
```

### Serviços Disponíveis
| Serviço         | URL                          | Credenciais              |
|-----------------|------------------------------|--------------------------|
| Airflow         | http://localhost:8080        | airflow:airflow          |
| MinIO Console   | http://localhost:9001        | minioadmin:minioadmin    |
| Spark UI        | http://localhost:8081        | -                        |
| Grafana         | http://localhost:3000        | admin:admin              |
| Streamlit       | http://localhost:8501        | -                        |

### Automação Default
O script cria automaticamente:
- Usuário admin no Airflow com senha default.
- Conexão entre Airflow e PostgreSQL
- Instância do Streamlit
- Streamlit e Arflow pré-configurados.

## Modo de uso:
```bash
# Execute o script de criação (opcional: passe o nome do projeto como parâmetro)
# caso não seja informado um nome, por default ele criará um projeto nomeado data-engineering

sh setup_project.sh [nome-do-projeto]
```
### Personalização
Edite o arquivo `.env` para ajustar:
- Versões dos serviços
- Credenciais
- Configurações de memória do Spark
- Portas dos serviços

### Comandos Úteis
```bash
# Faz o build e iniciar todos os serviços
./start_project.sh

# Parar todos os serviços
./stop_project.sh

# Verificar status dos serviços
./check_services.sh

# Acessar logs (para identificar possíveis erros)
docker compose logs -f [serviço]
```

### Problemas mais comuns:
1. **Airflow não inicia**: 
   - Verifique se o PostgreSQL está saudável (`docker compose ps`)

2. **Usuário não conecta no Web Server do Airflow**:
   - Verifique a credencial criada no .env

3. **Serviços não se comunicam**:
   - Verifique a rede Docker (`docker network ls`)
   - Confirme que todos os serviços estão no mesmo network

4. **Verificar a saúde dos serviços**:
   - Rodar o script (`./check_services.sh`)

5. **Erros desconhecidos nos serviços**
   - Verificar o log do serviço (`docker compose logs -f [serviço]`)

## Melhorias a serem implementadas
- Adicionar Jupyter Notebook para análise
- Adicionar exemplos de jobs Spark
- Configurar alertas no Grafana
- Incluir Kafka para streaming
