
FROM python:3.7
USER root
RUN apt-get update && apt-get install --yes \
    sudo \
    git \
    vim \
    cron \
    gcc \
    g++ \
    unzip
RUN pip install apache-airflow[1.10.10]
RUN cd /usr/local && mkdir airflow && chmod +x airflow && cd airflow
RUN useradd -ms /bin/bash airflow
RUN usermod -a -G sudo airflow
RUN chmod 666 -R /usr/local/airflow
ARG AIRFLOW_USER_HOME=/usr/local/airflow
ENV AIRFLOW_HOME=${AIRFLOW_USER_HOME}
COPY config/airflow.cfg ${AIRFLOW_USER_HOME}/airflow.cfg
EXPOSE 8080 
#Python Package Dependencies for Airflow 
RUN pip install pyodbc flask-bcrypt pymssql sqlalchemy psycopg2-binary pymysql

#DAGS
COPY config/airflow.cfg ${AIRFLOW_USER_HOME}/airflow.cfg

#Remote Logging Setup
RUN cd ${AIRFLOW_HOME} && mkdir logs && chmod +x -R logs
COPY /config/gcp.json /usr/local/airflow/gcp.json
RUN cd /usr/local/airflow && mkdir config && chmod +x -R config 
COPY config/__init__.py /usr/local/airflow/config/__init__.py
COPY config/log_config.py /usr/local/airflow/config/log_config.py
RUN cd  /usr/local/airflow/logs && mkdir scheduler && chmod +x -R scheduler

#GCP packages for airflow
RUN pip install apache-airflow[gcp] apache-airflow[gcp-api]
RUN echo "deb http://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list
RUN apt-get install gnupg -y
RUN curl https://packages.cloud.google.com/apt/doc/apt-key.gpg |  apt-key add -
RUN apt-get update && apt-get install google-cloud-sdk -y
RUN gcloud auth activate-service-account <insert your servivce account>  --key-file=/usr/local/airflow/gcp.json --project=<your project name>
#Kubernetes
RUN pip install apache-airflow[kubernetes]
#Environmental Variables
ENV AIRFLOW__CORE__FERNET_KEY=<your_fernet_key>
ENV AIRFLOW__CORE__TASK_LOG_READER=gcs.task
ENV AIRFLOW__CORE__REMOTE_LOG_CONN_ID=AirflowGCPKey
ENV AIRFLOW__CORE__REMOTE_BASE_LOG_FOLDER=gs://<your-gcp_bucket>/logs
ENV AIRFLOW__CORE__LOGGING_LEVEL=INFO
ENV AIRFLOW__CORE__LOGGING_CONFIG_CLASS=log_config.LOGGING_CONFIG
ENV AIRFLOW__CORE__ENCRYPT_S3_LOGS=False
ENV AIRFLOW__CORE__EXECUTOR=KubernetesExecutor

#Kubernetes Environmental Variables
ENV AIRFLOW__KUBERNETES_ENVIRONMENT_VARIABLES__AIRFLOW__CORE__REMOTE_LOGGING=True
ENV AIRFLOW__KUBERNETES_ENVIRONMENT_VARIABLES__AIRFLOW__CORE__LOGGING_CONFIG_CLASS=log_config.LOGGING_CONFIG
ENV AIRFLOW__KUBERNETES_ENVIRONMENT_VARIABLES__AIRFLOW__CORE__TASK_LOG_READER=gcs.task
ENV AIRFLOW__KUBERNETES_ENVIRONMENT_VARIABLES__AIRFLOW__CORE__REMOTE_BASE_LOG_FOLDER=gs://<your-gcp-bucket>/logs
ENV AIRFLOW__KUBERNETES_ENVIRONMENT_VARIABLES__AIRFLOW__CORE__REMOTE_LOG_CONN_ID=AirflowGCPKey
ENV AIRFLOW__KUBERNETES_ENVIRONMENT_VARIABLES__AIRFLOW__WEBSERVER__LOG_FETCH_TIMEOUT_SEC=15
#To prevent Kubernetes API from timing out while running the airflow scheduler
ENV AIRFLOW__KUBERNETES_ENVIRONMENT_VARIABLES_KUBE_CLIENT_REQUEST_TIMEOUT_SEC=50

#INSERT YOUR PACKAGES HERE TO CUSTOMIZE YOUR IMAGE
#Python Packages for Azure 
RUN pip install azure-mgmt-compute azure-mgmt-storage azure-mgmt-resource azure-keyvault-secrets azure-storage-blob 
RUN pip install azure-storage-file-datalake --pre mysql-connector-python-rf

#INITIALIZING AIRFLOW'S DATABASE
RUN airflow initdb
#Supervisord
RUN apt-get update && apt-get install -y supervisor          
COPY /config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
RUN chmod +x /etc/supervisor/conf.d/supervisord.conf             
CMD ["/usr/bin/supervisord"]

