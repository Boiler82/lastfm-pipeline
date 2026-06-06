from airflow import DAG
from airflow.providers.standard.operators.python import PythonOperator
from airflow.providers.standard.operators.bash import BashOperator
from airflow.providers.common.sql.operators.sql import SQLExecuteQueryOperator
from datetime import datetime, timedelta
import requests
import json
import os
from azure.storage.blob import BlobServiceClient
from dotenv import load_dotenv

load_dotenv()

def fetch_and_upload():
    API_KEY = os.environ.get("LASTFM_API_KEY")
    URL = f"http://ws.audioscrobbler.com/2.0/?method=chart.gettoptracks&api_key={API_KEY}&format=json&limit=50"
    
    response = requests.get(URL)
    data = response.json()
    
    tracks = data["tracks"]["track"]
    for position, track in enumerate(tracks, start=1):
        track["chart_position"] = position
    
    timestamp = datetime.now().strftime("%Y-%m-%dT%H-%M")
    filename = f"/tmp/lastfm_top_tracks_{timestamp}.json"
    
    with open(filename, "w") as f:
        json.dump(data, f, indent=2)
    
    connection_string = os.environ.get("AZURE_CONNECTION_STRING")
    blob_service_client = BlobServiceClient.from_connection_string(connection_string)
    container_name = "lastfm-raw-data"
    
    with open(filename, "rb") as upload_data:
        blob_service_client.get_container_client(container_name).upload_blob(
            name=filename, data=upload_data, overwrite=True
        )
    print(f"Uploaded {filename} to Azure Blob Storage")

default_args = {
    'owner': 'fabio',
    'retries': 1,
    'retry_delay': timedelta(minutes=5)
}

with DAG(
    dag_id='lastfm_pipeline',
    default_args=default_args,
    start_date=datetime(2026, 6, 1),
    schedule='@daily',
    catchup=False
) as dag:

    fetch_upload = PythonOperator(
        task_id='fetch_and_upload_to_azure',
        python_callable=fetch_and_upload
    )

    copy_into_snowflake = SQLExecuteQueryOperator(
    task_id='copy_into_snowflake',
    conn_id='snowflake_default',
    sql="""
        COPY INTO LASTFM.RAW.TOP_TRACKS (RAW_DATA, LOADED_AT)
        FROM (
            SELECT 
                $1,
                TO_TIMESTAMP(
                    SUBSTR(SPLIT_PART(METADATA$FILENAME, '/', -1), 19, 16),
                    'YYYY-MM-DDTHH-MI'
                )
            FROM @LASTFM.RAW.AZURE_STAGE
        )
        FILE_FORMAT = (TYPE = 'JSON');
    """
)

    run_dbt = BashOperator(
        task_id='run_dbt_models',
        bash_command='dbt run --project-dir /usr/local/airflow/dags/../lastfm_dbt --profiles-dir /usr/local/airflow/dags/../lastfm_dbt'
    )

    fetch_upload >> copy_into_snowflake >> run_dbt