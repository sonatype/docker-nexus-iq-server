#### Nexus IQ Server

To run with ports 8070 (web UI) and 8071 (admin port) use:

    docker run -d -p 8070:8070 -p 8071:8071 --name nexus-iq-server sonatype/nexus-iq-server

or to let docker assign available ports use:

    docker run -d -p 8070 -p 8071 --name nexus-iq-server sonatype/nexus-iq-server

To get the assigned port or check if the server is running use:

    docker ps --filter "name=nexus-iq-server"

##### Build the Nexus IQ Server image

To build a docker image from the Dockerfile you can use this command:

    docker build --build-arg IQ_SERVER_VERSION=1.36.0-01 .

The following optional variables can be used when building the image:

- IQ_SERVER_VERSION: Version of Nexus IQ Server
- IQ_SERVER_SHA256: Check hash matches the downloaded IQ Server archive or else fail build. Required if `IQ_SERVER_VERSION` is provided.
- JAVA_URL: Download URL for Oracle JDK
- JAVA_SHA256: Check hash matches the downloaded JDK or else fail build. Required if `JAVA_URL` is provided.
- SONATYPE_WORK: Path to Nexus IQ Server working directory where variable data is stored

##### Testing the Dockerfile

We are using `rspec` as test framework. `serverspec` provides a docker backend (see the method `set` in the test code)
 to run the tests inside the docker container, and abstracts away the difference between distributions in the tests
 (e.g. yum, apt,...).

    rspec [--backtrace] spec/Dockerfile_spec.rb

##### Persistent Data

There are two general approaches to handling persistent storage requirements
with Docker. See [Managing Data in Containers](https://docs.docker.com/engine/tutorials/dockervolumes/)
for additional information.

  1. *Use a data volume*.  Since data volumes are persistent
  until no containers use them, a volume can be created specifically for
  this purpose.  This is the recommended approach.  

  ```
  $ docker volume create --name sonatype-work
  $ docker run -d -p 8070:8070 -p 8071:8071 --name nexus -v sonatype-work:/sonatype-work sonatype/nexus-iq-server
  ```

  2. *Mount a host directory as the volume*.  This is not portable, as it
  relies on the directory existing with correct permissions on the host.
  However it can be useful in certain situations where this volume needs
  to be assigned to certain specific underlying storage.  

  ```
  $ mkdir /some/dir/sonatype-work && chown -R 200 /some/dir/sonatype-work
  $ docker run -d -p 8070:8070 -p 8071:8071 --name nexus -v /some/dir/sonatype-work:/sonatype-work sonatype/nexus-iq-server
  ```

#### License

The cookbooks are licensed under the [Apache v2 license](LICENSE)
