FROM ubuntu:24.04

# Install system dependencies (including GPU relevant packages)
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

# Install Java 21, Gradle 8.7, Maven 3.9.6
RUN curl -s "https://get.sdkman.io" | bash
SHELL ["/bin/bash", "-lc"]

RUN source "$HOME/.sdkman/bin/sdkman-init.sh" && \
    sdk install java 21.0.2-tem && \
    sdk install gradle 8.7 && \
    sdk install maven 3.9.6

# Set environment variables globally
ENV SDKMAN_DIR="/root/.sdkman"
ENV JAVA_HOME="$SDKMAN_DIR/candidates/java/current"
ENV PATH="$JAVA_HOME/bin:$SDKMAN_DIR/candidates/maven/current/bin:$SDKMAN_DIR/candidates/gradle/current/bin:$PATH"

# Create logs directory
RUN mkdir -p /opt/logs

# Install Ollama and pull models
RUN curl -fsSL https://ollama.com/install.sh | tee /opt/logs/ollama_install.log | bash

RUN bash -lc "\
    ollama serve > /opt/logs/ollama_build_serve.log 2>&1 & \
    pid=\$!; sleep 5; \
    echo 'Pulling Gemma2:2b model...' && \
    ollama pull gemma2:2b > /opt/logs/gemma2_2b_download.log 2>&1; \
    kill \$pid; wait \$pid 2>/dev/null || true"

# Clone repositories: GIN and benchmark projects
RUN git clone https://github.com/gintool/gin.git /opt/gin && \
    cd /opt/gin && git checkout llm

RUN git clone https://github.com/jcodec/jcodec.git /opt/jcodec && \
    cd /opt/jcodec && git checkout 7e52834

# Replace Java source/target version in pom.xml to 21 for Jcodec
RUN find /opt/jcodec -name pom.xml -exec \
      sed -i 's|<source>[ ]*1\.6[ ]*</source>|<source>21</source>|g' {} \; && \
    find /opt/jcodec -name pom.xml -exec \
      sed -i 's|<target>[ ]*1\.6[ ]*</target>|<target>21</target>|g' {} \;

# Get relevant files from the gin-docker repo (notebook and profiling data)
RUN git clone https://github.com/domsob/gin-docker.git /opt/gin-docker && \
    cp /opt/gin-docker/profiling_data/jcodec.Profiler_output.csv /opt/jcodec/ && \
    cp /opt/gin-docker/gin_workflow.ipynb /opt/ && \
    rm -rf /opt/gin-docker

# Build GIN
RUN bash -c "source $HOME/.sdkman/bin/sdkman-init.sh && \
    cd /opt/gin && ./gradlew clean build 2>&1 | tee /opt/logs/gin_build_output.log"

# Build JCodec
RUN bash -c "source $HOME/.sdkman/bin/sdkman-init.sh && \
    cd /opt/jcodec && mvn clean compile 2>&1 | tee /opt/logs/jcodec_compile.log"

RUN bash -c "source $HOME/.sdkman/bin/sdkman-init.sh && \
    cd /opt/jcodec && mvn clean test 2>&1 | tee /opt/logs/jcodec_test.log"

# Install Jupyter
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

RUN pip install --upgrade pip setuptools wheel && \
    pip install notebook

# Start servers (Ollama and Jupyter)
EXPOSE 8888
WORKDIR /opt

CMD bash -lc "\
    mkdir -p /opt/logs && \
    echo 'Starting Ollama server...' && \
    ollama serve > /opt/logs/ollama_serve.log 2>&1 & \
    sleep 5 && \
    echo 'Starting Jupyter Notebook...' && \
    jupyter notebook --ip=0.0.0.0 --port=8888 --no-browser --allow-root --NotebookApp.token='' --NotebookApp.password='' --NotebookApp.disable_check_xsrf=True --notebook-dir=/opt"
