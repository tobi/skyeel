#!/bin/ruby

require 'pathname'
require 'net/ssh'
require 'yaml'


DOCKERFILE_CONTENT = <<~DOCKERFILE
  FROM nvidia/cuda:12.5.0-runtime-ubuntu22.04 as base
  RUN apt update
  RUN apt install -y git curl bash zsh wget python3.11 python3-pip

  RUN pip3 install uv
  RUN uv venv /venv
  ENV PATH /venv/bin:$PATH
  RUN . /venv/bin/activate
  COPY entrypoint.sh /entrypoint.sh
  RUN chmod +x /entrypoint.sh
  WORKDIR /workdir

  VOLUME /workdir
  ENTRYPOINT ["/entrypoint.sh"]
  DOCKERFILE

RUNTIME_FILE = <<~RUNTIME_FILE
  #!/bin/bash
  set -e
  set -x
  SKYEEL_DIR=$(dirname $PWD)

  SETUP=$(cat $SKYEEL_DIR/tasks.setup.sh)
  SETUP_HASH=$(cat $SKYEEL_DIR/tasks.setup.sh | md5sum | cut -d ' ' -f 1)

  RUN=$(cat $SKYEEL_DIR/tasks.run.sh)
  # RUN_HASH=$(cat $SKYEEL_DIR/tasks.run.sh | md5sum | cut -d ' ' -f 1)

  IMAGE_ID="skyeel"
  RUN_NAME="skyeel-$(date +%m-%d.%H-%M)"

  DOCKER_RUN_CMD="docker run -v $HOME/.cache:/root/.cache -v $SKYEEL_DIR/workdir:/workdir --env-file $SKYEEL_DIR/.env "

  echo $DOCKER_RUN_CMD
  echo "Running task $RUN_NAME"
  docker build -q -t $IMAGE_ID $SKYEEL_DIR

  echo "* -- SETUP -----------------------"
  CONTAINER_ID=$($DOCKER_RUN_CMD -t $SETUP_HASH -d $IMAGE_ID bash -c "$SETUP")

  docker logs -f $CONTAINER_ID
  IMAGE_ID=$(docker commit $CONTAINER_ID)
  docker rm $CONTAINER_ID

  echo "* -- RUN -------------------------"
  CONTAINER_ID=$($DOCKER_RUN_CMD -t $RUN_NAME -d $IMAGE_ID bash -c "$RUN")

  docker logs -f $CONTAINER_ID
  # actually, let's kleep the container around for accessing its files later in a pinch
  # IMAGE_ID=$(docker commit $CONTAINER_ID $RUN_NAME)
  # docker rm $CONTAINER_ID

  echo "Finsihed run $RUN_NAME, "
  echo "  copied /workdir/output to $SKYEEL_DIR/workdir/output/$RUN_NAME"
  echo "  copy additional files from the container via:"
  echo "  docker cp $RUN_NAME:/workdir/output ~/Downloads/output"

  RUNTIME_FILE

ENTRYPOINT_FILE = <<~ENTRYPOINT_FILE
  #!/bin/bash
  # This script is the entrypoint for the docker container
  #
  # Activate the virtual environment
  source /venv/bin/activate

  # Execute the script passed as an argument
  exec "$@"
ENTRYPOINT_FILE

class Session
  def initialize(ssh)
    @ssh = ssh
  end

  # Function to check if Docker is installed
  def check_docker_installed()
    output = @ssh.exec!("docker --version")
    unless output && output.include?("Docker version")
      raise "Docker is not installed on the server."
    end
    puts output
  end

  def run(cmd)
    output = ""
    @ssh.exec!(cmd) do |channel, stream, data|
      @ssh.loop(0.1) { !@ssh.busy? }
      puts data
      output << data
    end

    output.lines[-1].strip if output.lines.any?
  end

  def write_file(file_path, content)
    run("echo '#{content}' > #{file_path}")
  end
end

def assemble_env_file(env)
  env.collect do |k,v|

    # if its an empty value, get it from the current machine ENV
    if v.nil? or v == ""
      puts "Getting value for #{k} from local ENV"
      v = ENV[k] || ""
    end

    "#{k}=#{v}"
  end.join("\n")
end

def main
  if ARGV.length != 2
    puts "Usage: skyeel <server> <skypilot_file_path>"
    exit 1
  end

  server = ARGV[0]
  user = ENV['USER']
  puts "Connecting to server: #{server} as user: #{user}"

  skyfile = Pathname.new(ARGV[1])
  skydir = skyfile.dirname.realpath
  config = YAML.load_file(skyfile)

  puts "Using skyfile: #{skyfile}, uploading workdir: #{skydir}"

  setup_script, run_script, name, envs = config.values_at('setup', 'run', 'name', 'envs')

  if name.nil?
    puts "skyeel config needs `name` set"
    exit 1
  end


  Net::SSH.start(server, user) do |ssh|
    session = Session.new(ssh)

    env = { "NAME" => name, "PROJECT_NAME" => name, "workdir" => "." }.update(envs || {})

    rundir = "~/skyeel/runs/#{name}"
    workdir = "#{rundir}/workdir"

    session.check_docker_installed()
    session.run("mkdir -p #{workdir}")
    session.write_file("#{rundir}/.env", assemble_env_file(env))
    session.write_file("#{rundir}/tasks.setup.sh", setup_script)
    session.write_file("#{rundir}/tasks.run.sh", run_script)
    session.write_file("#{rundir}/runner.sh", RUNTIME_FILE)
    session.write_file("#{rundir}/Dockerfile", DOCKERFILE_CONTENT)
    session.write_file("#{rundir}/entrypoint.sh", ENTRYPOINT_FILE)

    system("cd #{skydir} && rsync -art --progress #{skydir}/ #{server}:#{workdir}/")

    session.run("cd ~/skyeel/run/workdir && bash ../runner.sh")
  end
end

main if __FILE__ == $0
