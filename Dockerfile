
FROM python:3.7
# supervisord setup                       
RUN apt-get update && apt-get install -y supervisor  
USER root
RUN apt-get update && apt-get install --yes \
    sudo \
    git \
    vim \
    cron \
    unixodbc \
    unixodbc-dev \
    freetds-bin \
    freetds-dev \
    gcc \
    g++ \
    libffi-dev \
    libc-dev \
    libxml2 \
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

ENV AIRFLOW__CORE__EXECUTOR=LocalExecutor #Setting Executor to Local temporarily

#SQL DRIVER Setup 
RUN echo tdsodbc freetds/addtoodbc boolean true | debconf-set-selections
RUN apt-get update && apt-get install tdsodbc 
COPY /config/obdcinst.ini /etc/obdcinst.ini
#Python Package Dependencies for Airflow 
RUN pip install pyodbc flask-bcrypt pymssql sqlalchemy psycopg2-binary pymysql

#DAGS
RUN cd ${AIRFLOW_HOME} && mkdir dags && chmod +x -R dags
COPY config/airflow.cfg ${AIRFLOW_USER_HOME}/airflow.cfg
#Git Setup. Add your SSH keys to the config folder
ADD /config/id_rsa ~/.ssh/id_rsa 
ADD /config/id_rsa.pub ~/.ssh/id_rsa.pub
ADD /config/authorized_keys ~/.ssh/authorized_keys
ADD /config/known_hosts ~/.ssh/known_hosts
RUN chmod +x ~/.ssh/id_rsa
RUN chmod +x ~/.ssh/id_rsa.pub
RUN cd ${AIRFLOW_USER_HOME}/dags && git init && git remote add dags <insert your git repo here>
#Cron Setup
COPY config/git_sync /etc/cron.d/git_sync
RUN chmod 0644 /etc/cron.d/git_sync
COPY config/git_sync /etc/cron.d/git_sync
RUN chmod 0644 /etc/cron.d/git_sync
RUN crontab /etc/cron.d/git_sync
#Testing cron job and git_sync.sh so that dags folder syncs with bitbucket repo
RUN cd ~ && chmod +x git_sync.sh && ./git_sync.sh --yes

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
#RUN gcloud auth activate-service-account <insert your servivce account>  --key-file=/usr/local/airflow/gcp.json --project=<your project name>
RUN airflow run add_gcp_connection add_gcp_connection_python 2010-01-0
#Kubernetes
RUN pip install apache-airflow[kubernetes]
#Environmental Variables
ENV AIRFLOW__CORE__FERNET_KEY=your_fernet_key
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

#INTIALZING AIRFLOW'S DATABASE
RUN airflow initdb
#Supervisord
RUN apt-get update && apt-get install -y supervisor          
COPY /config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
RUN chmod +x /etc/supervisor/conf.d/supervisord.conf             
CMD ["/usr/bin/supervisord"]

