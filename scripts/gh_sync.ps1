Param()

$ErrorActionPreference = 'Stop'

function Get-RepoSlug {
  $remoteUrl = git remote get-url origin 2>$null
  if (-not $remoteUrl) { throw "No 'origin' remote found" }
  if ($remoteUrl -match 'git@github.com:(?<org>[^/]+)/(?<repo>[^\.]+)(\.git)?$') {
    return "$($Matches['org'])/$($Matches['repo'])"
  }
  if ($remoteUrl -match 'https?://github.com/(?<org>[^/]+)/(?<repo>[^\.]+)(\.git)?$') {
    return "$($Matches['org'])/$($Matches['repo'])"
  }
  throw "Unrecognized remote URL format: $remoteUrl"
}

function Ensure-Label($repo, $name, $color, $desc) {
  $encoded = [uri]::EscapeDataString($name)
  $exists = $false
  try {
    & gh api -H 'Accept: application/vnd.github+json' ("repos/$repo/labels/$encoded") 1>$null 2>$null
    if ($LASTEXITCODE -eq 0) { $exists = $true }
  } catch { $exists = $false }
  if ($exists) {
    $args = @('api','-X','PATCH','-H','Accept: application/vnd.github+json',
      ("repos/$repo/labels/$encoded"),
      '-f',("new_name=$name"),'-f',("color=$color"),'-f',("description=$desc"))
    & gh @args 1>$null
  } else {
    $args = @('api','-X','POST','-H','Accept: application/vnd.github+json',
      ("repos/$repo/labels"),
      '-f',("name=$name"),'-f',("color=$color"),'-f',("description=$desc"))
    & gh @args 1>$null
  }
}

function Ensure-Issue($repo, $title, $body, $labels) {
  $qRaw = ('repo:{0} is:issue in:title "{1}"' -f $repo, $title)
  $q = [uri]::EscapeDataString($qRaw)
  $res = & gh api ("search/issues?q=$q&per_page=1") | ConvertFrom-Json
  if ($res.total_count -gt 0 -and $res.items.Count -gt 0) {
    $num = $res.items[0].number
    foreach ($l in $labels) { & gh issue edit -R $repo $num --add-label $l 1>$null }
    return
  }
  $labelArgs = @()
  foreach ($l in $labels) { $labelArgs += @('-l', $l) }
  & gh issue create -R $repo -t $title -b $body @labelArgs 1>$null
}

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
  Write-Error "GitHub CLI 'gh' not found. Install from https://cli.github.com/ and run 'gh auth login'."
}
gh auth status 1>$null 2>$null
if ($LASTEXITCODE -ne 0) {
  Write-Error "GitHub CLI not authenticated. Run: gh auth login"
}

$repo = Get-RepoSlug
Write-Host "Using repo: $repo"

# Label taxonomy
$labels = @(
  [pscustomobject]@{Name='type:bug';            Color='d73a4a'; Description="Something isn't working"}
  [pscustomobject]@{Name='type:enhancement';    Color='a2eeef'; Description='New feature or improvement'}
  [pscustomobject]@{Name='type:documentation';  Color='0075ca'; Description='Docs, README, or playbook work'}
  [pscustomobject]@{Name='type:task';           Color='cfd3d7'; Description='Actionable task'}
  [pscustomobject]@{Name='type:chore';          Color='d4c5f9'; Description='Build, tooling, maintenance'}

  [pscustomobject]@{Name='area:k8s';            Color='0e8a16'; Description='Kubernetes manifests & cluster'}
  [pscustomobject]@{Name='area:gpu';            Color='1f883d'; Description='NVIDIA drivers, operator, device plugin'}
  [pscustomobject]@{Name='area:docker';         Color='0366d6'; Description='Dockerfiles and images'}
  [pscustomobject]@{Name='area:data';           Color='fbca04'; Description='Datasets and storage'}
  [pscustomobject]@{Name='area:training';       Color='5319e7'; Description='PyTorch, DDP, nanoGPT config'}
  [pscustomobject]@{Name='area:monitoring';     Color='a2eeef'; Description='Logs, metrics, TensorBoard'}
  [pscustomobject]@{Name='area:ci';             Color='d876e3'; Description='CI/CD scripts and workflows'}

  [pscustomobject]@{Name='priority:P0';         Color='b60205'; Description='Critical'}
  [pscustomobject]@{Name='priority:P1';         Color='d93f0b'; Description='High'}
  [pscustomobject]@{Name='priority:P2';         Color='fbca04'; Description='Medium'}
  [pscustomobject]@{Name='priority:P3';         Color='e4e669'; Description='Low'}

  [pscustomobject]@{Name='status:blocked';      Color='e11d21'; Description='Blocked on external dependency'}
  [pscustomobject]@{Name='status:needs-info';   Color='c5def5'; Description='Needs clarification or data'}
  [pscustomobject]@{Name='status:ready';        Color='0e8a16'; Description='Ready to pick up'}

  [pscustomobject]@{Name='good first issue';    Color='7057ff'; Description='Good for newcomers'}
  [pscustomobject]@{Name='help wanted';         Color='008672'; Description='Contributions welcome'}

  [pscustomobject]@{Name='size:XS';             Color='ededed'; Description='< 30 min'}
  [pscustomobject]@{Name='size:S';              Color='c5def5'; Description='~1-2 hours'}
  [pscustomobject]@{Name='size:M';              Color='bfdadc'; Description='~1 day'}
  [pscustomobject]@{Name='size:L';              Color='c2e0c6'; Description='> 1 day'}

  [pscustomobject]@{Name='security';            Color='ee0701'; Description='Security implications'}
  [pscustomobject]@{Name='question';            Color='d876e3'; Description='Further information requested'}
)

Write-Host 'Syncing labels...'
foreach ($l in $labels) { Ensure-Label -repo $repo -name $l.Name -color $l.Color -desc $l.Description }

# Issues backlog
$issues = @(
  [pscustomobject]@{
    Title='Configure corporate proxy for Pods and builds';
    Body='Set HTTP_PROXY/HTTPS_PROXY/NO_PROXY in k8s/01-proxy-config.yaml and verify egress for dataset prep & pip.';
    Labels=@('type:task','area:k8s','priority:P0','status:ready','size:S')
  }
  [pscustomobject]@{
    Title='Install k3s and GPU Operator';
    Body='Install k3s and the NVIDIA GPU Operator (device plugin + toolkit). Validate device plugin Ready.';
    Labels=@('type:task','area:k8s','area:gpu','priority:P0','status:ready','size:S')
  }
  [pscustomobject]@{
    Title='Build and load nanoGPT CUDA 11.8 image into k3s containerd';
    Body='Use scripts/02_build_and_load_image.sh to build the Docker image and import into k3s containerd.';
    Labels=@('type:task','area:docker','priority:P1','status:ready','size:S')
  }
  [pscustomobject]@{
    Title='Create hostPath PV/PVC and verify write perms';
    Body='Apply k8s/storage and ensure /var/lib/disttrain exists and is writable by Pods.';
    Labels=@('type:task','area:k8s','priority:P1','status:ready','size:S')
  }
  [pscustomobject]@{
    Title='Dataset job: tiny Shakespeare char-level';
    Body='Run Job to generate train/val bin files and persist to PVC at /data/datasets/shakespeare_char.';
    Labels=@('type:task','area:data','priority:P1','status:ready','size:S')
  }
  [pscustomobject]@{
    Title='Single-Pod multi-GPU training (3x A10)';
    Body='Run Job requesting 3 GPUs and launch torchrun --standalone --nproc_per_node=3 with nanoGPT config.';
    Labels=@('type:enhancement','area:training','priority:P1','status:ready','size:M')
  }
  [pscustomobject]@{
    Title='Restore and validate multi-Pod DDP StatefulSet manifest';
    Body='Ensure headless Service + StatefulSet(3 replicas) and DDP rendezvous via MASTER_ADDR/PORT works end-to-end.';
    Labels=@('type:bug','area:k8s','area:training','priority:P1','status:ready','size:M')
  }
  [pscustomobject]@{
    Title='TensorBoard: document workflow and logdir conventions';
    Body='Document reading TensorBoard logs from /data/runs and safe copying off-cluster without exposing a service.';
    Labels=@('type:documentation','area:monitoring','priority:P2','status:ready','size:S')
  }
  [pscustomobject]@{
    Title='Add medium dataset Job (OpenWebText subset)';
    Body='Create a Job to pull a small OWT subset and prepare tokens, configurable size via env.';
    Labels=@('type:enhancement','area:data','priority:P2','status:ready','size:M','good first issue')
  }
  [pscustomobject]@{
    Title='NCCL tuning presets and docs (TCP only)';
    Body='Expose NCCL env toggles (e.g., IFNAME) and document impact on single-node TCP DDP.';
    Labels=@('type:documentation','area:training','priority:P2','status:ready','size:S')
  }
  [pscustomobject]@{
    Title='Add CI: lint YAML and shell scripts';
    Body='GitHub Actions workflow to run kubeval/yamllint and shellcheck on scripts.';
    Labels=@('type:chore','area:ci','priority:P3','status:ready','size:S','help wanted')
  }
)

Write-Host 'Creating issues...'
foreach ($i in $issues) { Ensure-Issue -repo $repo -title $i.Title -body $i.Body -labels $i.Labels }

Write-Host 'Done.'


