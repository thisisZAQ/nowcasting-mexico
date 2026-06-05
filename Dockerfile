# Dockerfile — nowcasting-mexico
# Reproduces the full analysis pipeline in a single container
# Usage: docker build -t nowcasting-mexico .
#        docker run -v $(pwd)/outputs:/project/outputs nowcasting-mexico

FROM rocker/r-ver:4.3.2

# System dependencies
RUN apt-get update && apt-get install -y \
    python3 python3-pip python3-venv \
    libcurl4-openssl-dev libssl-dev libxml2-dev \
    libfontconfig1-dev libharfbuzz-dev libfribidi-dev \
    libfreetype6-dev libpng-dev libtiff5-dev libjpeg-dev \
    gfortran liblapack-dev libblas-dev \
    graphviz \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /project

# Copy project files
COPY . .

# Install R packages via renv
RUN R -e "install.packages('renv', repos='https://cloud.r-project.org')"
RUN R -e "renv::restore(prompt=FALSE)"

# Install Python dependencies
RUN python3 -m venv .venv && \
    .venv/bin/pip install --upgrade pip && \
    .venv/bin/pip install -r environment/requirements.txt

# Create output directories
RUN mkdir -p outputs/figures outputs/tables outputs/manuscript \
             data/processed data/final logs

# Default command: print usage
CMD ["R", "-e", "cat('nowcasting-mexico container ready.\\nRun: snakemake --cores 4\\n')"]
