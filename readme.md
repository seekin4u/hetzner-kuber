~/Desktop/hetzner-kuber$ mkdir -p charts

~/Desktop/hetzner-kuber$ helm package ./helm -d charts
Successfully packaged chart and saved it to: charts/hello-world-0.1.0.tgz

~/Desktop/hetzner-kuber$ helm repo index charts --url https://raw.githubusercontent.com/seekin4u/hetzner-kuber/main/charts