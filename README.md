#### Nexus IQ Server

To run with ports 8070 (web UI) and 8071 (admin port) use:

    docker run -d -p 8070:8070 -p 8071:8071 --name nexus-iq-server sonatype/nexus-iq-server

or to let docker assign available ports use:

    docker run -d -p 8070 -p 8071 --name nexus-iq-server sonatype/nexus-iq-server

To get the assigned port or check if the server is running use:

    docker ps nexus-iq-server

##### To build the Nexus IQ Server the following optional variables can be used:

- IQ_SERVER_VERSION: Version of Nexus IQ Server
- IQ_SERVER_SHA256: Check hash matches the downloaded IQ Server archive or else fail build. Required if `IQ_SERVER_VERSION` is provided.
- JAVA_URL: Download URL for Oracle JDK
- JAVA_SHA256: Check hash matches the downloaded JDK or else fail build. Required if `JAVA_URL` is provided.
- SONATYPE_WORK: Path to Nexus IQ Server working directory where variable data is stored


    docker build --build-arg IQ_SERVER_VERSION=1.36.0-01 .

##### Testing the Dockerfile

We are using `rspec` as test framework. `serverspec` provides a docker backend (see the method `set` in the test code)
 to run the tests inside the docker container, and abstracts away the difference between distributions in the tests
 (e.g. yum, apt,...).


    rspec [--backtrace] spec/Dockerfile_spec.rb

#### License

The cookbooks are licensed under the [Apache v2 license](LICENSE)
