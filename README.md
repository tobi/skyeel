# Skyeel

mini reimplementation of skypilot, so that you can run a standard and unmodified skypilot.yml file on a remote ssh server.


## Usage

```bash
  skyeel.rb <server name> <skypilot.yml>
```

## Example

  Train stable diffusion on my good boy:

  ```bash
    skyeel.rb a100-gcp examples/sdxl/skypilot.yml
  ```

  See the [examples](examples) directory for how this works. A100 server not included.


## Installation

  ```bash
    gem build skyeel.gemspec
    gem install skyeel-*
  ```