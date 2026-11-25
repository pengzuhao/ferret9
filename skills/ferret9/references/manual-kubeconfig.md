# kubeconfig

凭据是一整份 kubeconfig。交给 kubectl 时只加 `--kubeconfig <临时文件>`，不设置 `KUBECONFIG`。`ferret9 run` 已按这个方式代发。

来源：[kubectl Quick reference](https://kubernetes.io/docs/reference/kubectl/quick-reference/)。下面几条是该页的只读例子，`--kubeconfig` 由 ferret9 补上。

```text
ferret9 run <名称> -- kubectl get ns
ferret9 run <名称> -- kubectl get pods -n <ns>
ferret9 run <名称> -- kubectl get pods -n <ns> -o wide
ferret9 run <名称> -- kubectl describe pod <pod> -n <ns>
ferret9 run <名称> -- kubectl logs <pod> -n <ns> --tail=100
```

`get secret` 会把 Secret 的 data 打出来，不用来探活。`apply`、`delete`、`exec` 是写或进容器，须用户确认后再加 `--reviewed`。

2026-11-25 用 `kubectl get ns` 探过，返回了命名空间列表。
