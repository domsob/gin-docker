# ---------------------------------------------------------------
# Base Image
# ---------------------------------------------------------------
FROM ubuntu:24.04

# ---------------------------------------------------------------
# Install system dependencies (including GPU detection tools)
# ---------------------------------------------------------------
RUN apt-get update && apt-get install -y \
    zip \
    unzip \
    curl \
    git \
    nano \
    ca-certificates \
    python3 \
    python3-venv \
    python3-dev \
    build-essential \
    pciutils \
    lshw \
    zstd \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------
# Install SDKMAN for Java, Maven, Gradle
# ---------------------------------------------------------------
RUN curl -s "https://get.sdkman.io" | bash

# Use bash login shell to enable SDKMAN in subsequent RUN commands
SHELL ["/bin/bash", "-lc"]

# Install Java, Gradle, Maven
RUN source "$HOME/.sdkman/bin/sdkman-init.sh" && \
    sdk install java 21.0.9-oracle && \
    sdk install gradle 8.7 && \
    sdk install maven 3.9.11

# Set environment variables globally
ENV SDKMAN_DIR="/root/.sdkman"
ENV JAVA_HOME="$SDKMAN_DIR/candidates/java/current"
ENV PATH="$JAVA_HOME/bin:$SDKMAN_DIR/candidates/maven/current/bin:$SDKMAN_DIR/candidates/gradle/current/bin:$PATH"

# ---------------------------------------------------------------
# Create logs directory
# ---------------------------------------------------------------
RUN mkdir -p /opt/logs

# ---------------------------------------------------------------
# Install Ollama (log output)
# ---------------------------------------------------------------
RUN curl -fsSL https://ollama.com/install.sh | tee /opt/logs/ollama_install.log | bash

# ---------------------------------------------------------------
# Copy the gin-docker repo data (for scripts, profiling data, notebook)
# ---------------------------------------------------------------
#RUN git clone https://github.com/domsob/gin-docker.git /opt/gin-docker
COPY profiling_data /opt/gin-docker/profiling_data
COPY pull_models.sh /opt/gin-docker/pull_models.sh
COPY test_ollama.py /opt/gin-docker/test_ollama.py
COPY gin_workflow.sh /opt/gin-docker/gin_workflow.sh
COPY gin_workflow.ipynb /opt/gin-docker/gin_workflow.ipynb
COPY config.ini /opt/gin-docker/config.ini

# ---------------------------------------------------------------
# Copy config (local), pull script and test script (from git)
# ---------------------------------------------------------------
COPY config.ini /opt/config.ini
RUN cp /opt/gin-docker/pull_models.sh /opt/pull_models.sh && \
    chmod +x /opt/pull_models.sh && \
    cp /opt/gin-docker/test_ollama.py /opt/test_ollama.py

# ---------------------------------------------------------------
# Pull local models defined in config.ini during build
# ---------------------------------------------------------------
RUN bash /opt/pull_models.sh --build /opt/config.ini

# ---------------------------------------------------------------
# Clone repositories: GIN and target projects
# ---------------------------------------------------------------
RUN git clone https://github.com/gintool/gin.git /opt/gin && \
    cd /opt/gin && git checkout llm && git submodule update --init --recursive --force

RUN git clone https://github.com/jcodec/jcodec.git /opt/jcodec && \
    cd /opt/jcodec && git checkout 7e52834
    
RUN git clone https://github.com/google/gson.git /opt/gson && \
    cd /opt/gson && git checkout gson-parent-2.13.2
    
RUN git clone https://github.com/junit-team/junit4.git /opt/junit4 && \
    cd /opt/junit4 && git checkout 71c33ce

RUN git clone https://github.com/apache/commons-net.git /opt/commons-net && \
    cd /opt/commons-net && git checkout rel/commons-net-3.10.0

RUN git clone https://github.com/karatelabs/karate.git /opt/karate && \
    cd /opt/karate && git checkout v2.0.2

RUN git clone https://github.com/biojava/biojava.git /opt/biojava && \
    cd /opt/biojava && git checkout 5a699eb6465509b853463ae34ec04c4d90bc2a54

RUN git clone https://github.com/locationtech/spatial4j.git /opt/spatial4j && \
    cd /opt/spatial4j && git checkout f0d545dbb92ab560dea0aeb2b3d3a7ec53677ced

RUN git clone https://github.com/apache/opennlp.git /opt/opennlp && \
    cd /opt/opennlp && git checkout 91e4d3d0e589dff09f2382cb8100eb22facebf88

RUN git clone https://github.com/mybatis/mybatis-3.git /opt/mybatis-3 && \
    cd /opt/mybatis-3 && git checkout 59a0bcab2b3ebecb2569c1b33173d5ad9c6be152

RUN git clone https://github.com/alibaba/arthas.git /opt/arthas && \
    cd /opt/arthas && git checkout arthas-all-4.1.5


# ---------------------------------------------------------------
# Replace settings in pom.xml's
# ---------------------------------------------------------------

# Change Java source/target version in pom.xml to 21 for Jcodec
RUN find /opt/jcodec -name pom.xml -exec \
      sed -i 's|<source>[ ]*1\.6[ ]*</source>|<source>21</source>|g' {} \; && \
    find /opt/jcodec -name pom.xml -exec \
      sed -i 's|<target>[ ]*1\.6[ ]*</target>|<target>21</target>|g' {} \;

# Remove line in Gson's pom.xml
RUN sed -i '/<argLine>--illegal-access=deny<\/argLine>/d' /opt/gson/pom.xml

# Commons Net: disable apache-rat-plugin
RUN sed -i '140a\
<plugin>\n\
  <groupId>org.apache.rat</groupId>\n\
  <artifactId>apache-rat-plugin</artifactId>\n\
  <configuration>\n\
    <skip>true</skip>\n\
  </configuration>\n\
</plugin>' /opt/commons-net/pom.xml

# biojava - SCOP files for biojava on an unreliable URL. This patches the test to use a more reliable one.
RUN cd /opt/biojava && \
    perl -0777 -i -pe 's|https://scop\.berkeley\.edu/downloads/parse/|https://ftp.ebi.ac.uk/pub/databases/pdbe-kb/scop-legacy/parse/|g' biojava-structure/src/main/java/org/biojava/nbio/structure/scop/ScopInstallation.java && \
    perl -0777 -i -pe 's/assertEquals\("2GS2\.A",\s*s\.getName\(\)\);/assertTrue("Unexpected name: " + s.getName(), s.getName().equals("2GS2.A") || s.getName().startsWith("2GS2.A_"));/g' biojava-structure/src/test/java/org/biojava/nbio/structure/TestAtomCache.java && \
    perl -i -pe 's/^\s*@Test/\/\/ @Test/' "biojava-integrationtest/src/test/java/org/biojava/nbio/structure/test/cath/CathDomainTest.java" && \
    perl -i -pe 's/^\s*@Test/\/\/ @Test/' "biojava-integrationtest/src/test/java/org/biojava/nbio/structure/test/ecod/EcodInstallationTest.java"

# arthas - patch root-sensitive FileUtils test so it passes in Docker when run as root
RUN perl -0pi -e 's/\@Test\s+public void testOpenOutputStreamCannotWrite\(\) throws IOException \{/\@org.junit.Ignore("Fails when running tests as root in Docker")\n    \@Test\n    public void testOpenOutputStreamCannotWrite() throws IOException {/s' \
    /opt/arthas/core/src/test/java/com/taobao/arthas/core/util/FileUtilsTest.java

# ---------------------------------------------------------------
# Copy profiling data and notebook from gin-docker, then clean up
# ---------------------------------------------------------------
RUN cp /opt/gin-docker/profiling_data/jcodec.Profiler_output.csv_top10.csv /opt/jcodec/jcodec.Profiler_output.csv && \
    cp /opt/gin-docker/profiling_data/commons-net.Profiler_output.csv_top10.csv /opt/commons-net/commons-net.Profiler_output.csv && \
    cp /opt/gin-docker/profiling_data/gson.Profiler_output.csv_top10.csv /opt/gson/gson.Profiler_output.csv && \
    cp /opt/gin-docker/profiling_data/junit4.Profiler_output.csv_top10.csv /opt/junit4/junit4.Profiler_output.csv && \
    cp /opt/gin-docker/profiling_data/karate.Profiler_output.csv_top10.csv /opt/karate/karate.Profiler_output.csv && \
    cp /opt/gin-docker/profiling_data/biojava.Profiler_output.csv_top10.csv /opt/biojava/biojava.Profiler_output.csv && \
    cp /opt/gin-docker/profiling_data/spatial4j.Profiler_output.csv_top10.csv /opt/spatial4j/spatial4j.Profiler_output.csv && \
    cp /opt/gin-docker/profiling_data/opennlp.Profiler_output.csv_top10.csv /opt/opennlp/opennlp.Profiler_output.csv && \
    cp /opt/gin-docker/profiling_data/mybatis-3.Profiler_output.csv_top10.csv /opt/mybatis-3/mybatis-3.Profiler_output.csv && \
    cp /opt/gin-docker/profiling_data/arthas.Profiler_output.csv_top10.csv /opt/arthas/arthas.Profiler_output.csv && \
    cp /opt/gin-docker/gin_workflow.ipynb /opt/ && \
    cp /opt/gin-docker/gin_workflow.sh /opt/ && \
    rm -rf /opt/gin-docker

# ---------------------------------------------------------------
# Build GIN with log output
# ---------------------------------------------------------------
RUN bash -c "source $HOME/.sdkman/bin/sdkman-init.sh && \
    cd /opt/gin && ./gradlew clean build 2>&1 | tee /opt/logs/gin_build_output.txt"

# ---------------------------------------------------------------
# Build JCodec (compile + test) with logs
# ---------------------------------------------------------------
RUN bash -c "source $HOME/.sdkman/bin/sdkman-init.sh && \
    cd /opt/jcodec && mvn clean compile 2>&1 | tee /opt/logs/jcodec_compile.log"

RUN bash -c "source $HOME/.sdkman/bin/sdkman-init.sh && \
    cd /opt/jcodec && mvn clean test 2>&1 | tee /opt/logs/jcodec_test.log"
    
# ---------------------------------------------------------------
# Build Gson (compile + test) with logs
# ---------------------------------------------------------------
RUN bash -c "source $HOME/.sdkman/bin/sdkman-init.sh && \
    cd /opt/gson && mvn clean compile 2>&1 | tee /opt/logs/gson_compile.log"

RUN bash -c "source $HOME/.sdkman/bin/sdkman-init.sh && \
    cd /opt/gson && mvn clean install 2>&1 | tee /opt/logs/gson_test.log"

# ---------------------------------------------------------------
# Build JUnit4 (compile + test-compile + test as non-root) with logs
# ---------------------------------------------------------------
RUN bash -lc 'set -o pipefail && \
    source "$HOME/.sdkman/bin/sdkman-init.sh" && \
    cd /opt/junit4 && \
    mvn clean compile 2>&1 | tee /opt/logs/junit4_compile.log'

RUN bash -lc 'set -o pipefail && \
    source "$HOME/.sdkman/bin/sdkman-init.sh" && \
    cd /opt/junit4 && \
    mvn -DskipTests test-compile 2>&1 | tee /opt/logs/junit4_testcompile.log'

RUN mkdir -p /tmp/.m2/repository && \
    chmod -R 777 /tmp/.m2 && \
    chmod o+rx /root && \
    chmod -R o+rwX /opt/junit4 /opt/logs && \
    HOME=/tmp runuser -u nobody -- bash -lc 'set -o pipefail && \
    export HOME=/tmp && \
    export JAVA_HOME=/root/.sdkman/candidates/java/current && \
    export PATH=/root/.sdkman/candidates/maven/current/bin:$JAVA_HOME/bin:$PATH && \
    cd /opt/junit4 && \
    mvn -Dmaven.repo.local=/tmp/.m2/repository test 2>&1 | tee /opt/logs/junit4_test.log'

# ---------------------------------------------------------------
# Build Commons-Net (compile + test) with logs
# ---------------------------------------------------------------
RUN bash -c "source $HOME/.sdkman/bin/sdkman-init.sh && \
    cd /opt/commons-net && mvn clean compile 2>&1 | tee /opt/logs/commons-net_compile.log"

RUN bash -c "source $HOME/.sdkman/bin/sdkman-init.sh && \
    cd /opt/commons-net && mvn clean test 2>&1 | tee /opt/logs/commons-net_test.log"

# ---------------------------------------------------------------
# Build Karate (compile + test) with logs
# ---------------------------------------------------------------
RUN bash -c "source $HOME/.sdkman/bin/sdkman-init.sh && \
    cd /opt/karate && mvn clean compile 2>&1 | tee /opt/logs/karate_compile.log"

RUN bash -c "source $HOME/.sdkman/bin/sdkman-init.sh && \
    cd /opt/karate && mvn clean test 2>&1 | tee /opt/logs/karate_test.log"

# ---------------------------------------------------------------
# Build Biojava (compile + test) with logs
# ---------------------------------------------------------------
RUN bash -c "source $HOME/.sdkman/bin/sdkman-init.sh && \
    cd /opt/biojava && mvn clean compile 2>&1 | tee /opt/logs/biojava_compile.log"

RUN bash -c "source $HOME/.sdkman/bin/sdkman-init.sh && \
    cd /opt/biojava && mvn clean test 2>&1 | tee /opt/logs/biojava_test.log"

# needed to ensure submodule dependencies in local maven repo
RUN bash -c "source $HOME/.sdkman/bin/sdkman-init.sh && \
    rm -rf /root/.m2/repository/org/biojava && \
    cd /opt/biojava && mvn -U -DskipTests install 2>&1 | tee /opt/logs/biojava_install.log"

# ---------------------------------------------------------------
# Build Spatial4j (compile + test) with logs
# ---------------------------------------------------------------
RUN bash -c "source $HOME/.sdkman/bin/sdkman-init.sh && \
    cd /opt/spatial4j && mvn clean compile 2>&1 | tee /opt/logs/spatial4j_compile.log"

RUN bash -c "source $HOME/.sdkman/bin/sdkman-init.sh && \
    cd /opt/spatial4j && mvn clean test 2>&1 | tee /opt/logs/spatial4j_test.log"

# ---------------------------------------------------------------
# Build Opennlp (compile + test) with logs
# ---------------------------------------------------------------
RUN bash -c "source $HOME/.sdkman/bin/sdkman-init.sh && \
    cd /opt/opennlp && mvn clean compile 2>&1 | tee /opt/logs/opennlp_compile.log"

RUN bash -c "source $HOME/.sdkman/bin/sdkman-init.sh && \
    cd /opt/opennlp && mvn clean test 2>&1 | tee /opt/logs/opennlp_test.log"

# ---------------------------------------------------------------
# Build Mybatis-3 (compile + test) with logs
# ---------------------------------------------------------------
RUN bash -c "source $HOME/.sdkman/bin/sdkman-init.sh && \
    cd /opt/mybatis-3 && ./mvnw clean compile 2>&1 | tee /opt/logs/mybatis-3_compile.log"

RUN bash -c "source $HOME/.sdkman/bin/sdkman-init.sh && \
    cd /opt/mybatis-3 && ./mvnw clean test 2>&1 | tee /opt/logs/mybatis-3_test.log"

# ---------------------------------------------------------------
# Build arthas (compile + test) with logs
# ---------------------------------------------------------------
# (Build arthas with vmtool installed first, then compile/test core)
RUN bash -lc 'set -o pipefail && \
    source "$HOME/.sdkman/bin/sdkman-init.sh" && \
    cd /opt/arthas && \
    ./mvnw -pl arthas-vmtool -am install -DskipTests 2>&1 | tee /opt/logs/arthas_vmtool_install.log'

RUN bash -lc 'set -o pipefail && \
    source "$HOME/.sdkman/bin/sdkman-init.sh" && \
    cd /opt/arthas && \
    ./mvnw -pl core -am compile -DskipTests 2>&1 | tee /opt/logs/arthas_core_compile.log'

RUN bash -lc 'set -o pipefail && \
    source "$HOME/.sdkman/bin/sdkman-init.sh" && \
    cd /opt/arthas && export TZ=UTC && \
    ./mvnw -pl core -am test 2>&1 | tee /opt/logs/arthas_core_test.log'

RUN bash -lc 'set -o pipefail && \
    source "$HOME/.sdkman/bin/sdkman-init.sh" && \
    cd /opt/arthas && \
    ./mvnw -pl boot -am -DskipTests test-compile 2>&1 | tee /opt/logs/arthas_boot_testcompile.log'

RUN bash -lc 'set -o pipefail && \
    source "$HOME/.sdkman/bin/sdkman-init.sh" && \
    cd /opt/arthas && \
    ./mvnw -pl labs/arthas-grpc-server -am -DskipTests test-compile 2>&1 | tee /opt/logs/arthas_grpc_testcompile.log'



# ---------------------------------------------------------------
# Create Python virtual environment and install Jupyter
# ---------------------------------------------------------------
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

RUN pip install --upgrade pip setuptools wheel && \
    pip install notebook requests joblib litellm scikit-learn

# ---------------------------------------------------------------
# Expose Jupyter port
# ---------------------------------------------------------------
EXPOSE 8888
WORKDIR /opt

# ---------------------------------------------------------------
# Start Ollama, pull new models, run test, then start Jupyter
# ---------------------------------------------------------------
CMD bash -lc "\
    mkdir -p /opt/logs && \
    echo 'Starting Ollama server...' && \
    ollama serve > /opt/logs/ollama_serve.log 2>&1 & \
    sleep 5 && \
    echo 'Checking for new models to pull...' && \
    bash /opt/pull_models.sh --runtime /opt/config.ini 2>&1 | tee /opt/logs/model_pull.log && \
    echo 'Running Ollama test...' && \
    python3 /opt/test_ollama.py 2>&1 | tee /opt/logs/ollama_test.log && \
    echo 'Starting Jupyter Notebook...' && \
    jupyter notebook --ip=127.0.0.1 --port=8888 --no-browser --allow-root --NotebookApp.token='' --NotebookApp.password='' --NotebookApp.disable_check_xsrf=True --notebook-dir=/opt"
