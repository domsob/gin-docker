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
    ca-certificates \
    python3 \
    python3-venv \
    python3-dev \
    build-essential \
    pciutils \
    lshw \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------
# Install SDKMAN for Java, Maven, Gradle
# ---------------------------------------------------------------
RUN curl -s "https://get.sdkman.io" | bash

# Use bash login shell to enable SDKMAN for subsequent RUN commands
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
#RUN curl -fsSL https://ollama.com/install.sh | tee /opt/logs/ollama_install.log | bash

# ---------------------------------------------------------------
# Start Ollama server temporarily during build to pull model
# ---------------------------------------------------------------
#RUN bash -lc "\
#    ollama serve > /opt/logs/ollama_build_serve.log 2>&1 & \
#    pid=\$!; sleep 5; \
#    echo 'Pulling Gemma2:2b model...' && \
#    ollama pull gemma2:2b > /opt/logs/gemma2_2b_download.log 2>&1; \
#    kill \$pid; wait \$pid 2>/dev/null || true"

# ---------------------------------------------------------------
# Clone repositories: GIN and JCodec
# ---------------------------------------------------------------
RUN git clone https://github.com/gintool/gin.git /opt/gin && \
    cd /opt/gin && git checkout llm

RUN git clone https://github.com/jcodec/jcodec.git /opt/jcodec && \
    cd /opt/jcodec && git checkout 7e52834
    
RUN git clone https://github.com/google/gson.git /opt/gson && \
    cd /opt/gson && git checkout gson-parent-2.13.2
    
RUN git clone https://github.com/junit-team/junit4.git /opt/junit4 && \
    cd /opt/junit4 && git checkout 71c33ce

RUN git clone https://github.com/apache/commons-net.git /opt/commons-net && \
    cd /opt/commons-net && git checkout rel/commons-net-3.10.0

RUN git clone https://github.com/karatelabs/karate.git /opt/karate && \
    cd /opt/karate && git checkout v1.4.1

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

# ---------------------------------------------------------------
# Clone gin-docker repo to copy profiling data and notebook
# ---------------------------------------------------------------
#RUN git clone https://github.com/domsob/gin-docker.git /opt/gin-docker && \
#    cp /opt/gin-docker/profiling_data/jcodec.Profiler_output.csv /opt/jcodec/ && \
#    cp /opt/gin-docker/gin_workflow.ipynb /opt/ && \
#    rm -rf /opt/gin-docker
    
RUN git clone https://github.com/domsob/gin-docker.git /opt/gin-docker && \
    cp /opt/gin-docker/profiling_data/jcodec.Profiler_output.csv /opt/jcodec/ && \
    cp /opt/gin-docker/profiling_data/commons-net.Profiler_output.csv /opt/commons-net/ && \
    cp /opt/gin-docker/profiling_data/gson.Profiler_output.csv /opt/gson/ && \
    cp /opt/gin-docker/profiling_data/junit4.Profiler_output.csv /opt/junit4/ && \
    cp /opt/gin-docker/profiling_data/karate-core.Profiler_output.csv /opt/karate/ && \
    cp /opt/gin-docker/gin_workflow.ipynb /opt/ && \
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
    cd /opt/gson && mvn clean test 2>&1 | tee /opt/logs/gson_test.log"

# ---------------------------------------------------------------
# Build JUnit4 (compile + test) with logs
# ---------------------------------------------------------------
RUN bash -c "source $HOME/.sdkman/bin/sdkman-init.sh && \
    cd /opt/junit4 && mvn clean compile 2>&1 | tee /opt/logs/junit4_compile.log"

RUN bash -c "source $HOME/.sdkman/bin/sdkman-init.sh && \
    cd /opt/junit4 && mvn clean test 2>&1 | tee /opt/logs/junit4_test.log"

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
    cd /opt/karate/karate-core && mvn clean compile 2>&1 | tee /opt/logs/karate_compile.log"

RUN bash -c "source $HOME/.sdkman/bin/sdkman-init.sh && \
    cd /opt/karate/karate-core && mvn clean test 2>&1 | tee /opt/logs/karate_test.log"

# ---------------------------------------------------------------
# Create Python virtual environment and install Jupyter
# ---------------------------------------------------------------
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

RUN pip install --upgrade pip setuptools wheel && \
    pip install notebook

# ---------------------------------------------------------------
# Expose Jupyter port
# ---------------------------------------------------------------
EXPOSE 8888
WORKDIR /opt

# ---------------------------------------------------------------
# Start Ollama server and Jupyter Notebook
# ---------------------------------------------------------------
#CMD bash -lc "\
#    mkdir -p /opt/logs && \
#    echo 'Starting Ollama server...' && \
#    ollama serve > /opt/logs/ollama_serve.log 2>&1 & \
#    sleep 5 && \
#    echo 'Starting Jupyter Notebook...' && \
#    jupyter notebook --ip=0.0.0.0 --port=8888 --no-browser --allow-root --NotebookApp.token='' --NotebookApp.password='' --NotebookApp.disable_check_xsrf=True --notebook-dir=/opt"
    
CMD bash -lc "\
    mkdir -p /opt/logs && \
    echo 'Starting Jupyter Notebook...' && \
    jupyter notebook --ip=0.0.0.0 --port=8888 --no-browser --allow-root --NotebookApp.token='' --NotebookApp.password='' --NotebookApp.disable_check_xsrf=True --notebook-dir=/opt"
