#### Nexus IQ Server

To run with ports 8070 (web UI) and 8071 (admin port) use:

    docker run -d -p 8070:8070 -p 8071:8071 --name nexus-iq-server sonatype/nexus-iq-server

or to let docker assign available ports use:

    docker run -d -p 8070 -p 8071 --name nexus-iq-server sonatype/nexus-iq-server

To get the assigned port or check if the server is running use:

    docker ps nexus-iq-server

##### To build the Nexus IQ Server the following optional variables can be used:

- iqVersion: Version of Nexus IQ Server
- iqSha256: Check hash matches the downloaded IQ Server archive or else fail build. Required if iqVersion is provided.
- javaUrl: Download URL for Oracle JDK
- javaSha256: Check hash matches the downloaded JDK or else fail build. Required if javaUrl is provided.
- sonatypeWork: Path to Nexus IQ Server working directory where variable data is stored


    docker build --build-arg iqVersion=1.36.0-01 .


#### License

The cookbooks are licensed under the [Apache v2 license](LICENSE)
