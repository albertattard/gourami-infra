# Run application locally

- Start

  ```shell
  $ docker compose --file docker-compose.yaml up --detach
  ```

  Access application: [http://localhost:8000/](http://localhost:8000/).

- Stop

  ```shell
  $ docker compose --file docker-compose.yaml down --remove-orphans
  ```
