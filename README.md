# k3s-gitops

Однонодовый кластер k3s, в котором всё, кроме самого k3s и Argo CD, создаётся из этого репозитория по схеме app of apps. Удобно как домашняя лаборатория и как шаблон для небольшого прод-кластера.

```
bootstrap/root-app.yaml      Argo CD смотрит в apps/
apps/                        по Application на компонент, порядок через sync-wave
  ingress-nginx      wave 0
  cert-manager       wave 0
  cluster-issuer     wave 1  Let's Encrypt
  kube-prometheus-stack wave 1
  infra-lab          wave 2  приложение из github.com/Sakuratix/infra-lab
platform/                    values для чартов
```

## Старт

```bash
git clone https://github.com/Sakuratix/k3s-gitops && cd k3s-gitops
sudo ./install.sh
```

`install.sh` можно запускать повторно: он проверяет, что уже стоит, и доставляет только недостающее. Версии k3s и Argo CD зафиксированы в начале скрипта (`K3S_VERSION`, `ARGOCD_VERSION`), а не `stable`: один и тот же коммит всегда поднимает один и тот же кластер, а обновление проходит через PR.

Дальше любые изменения только через git: поменял values, сделал push, Argo CD синхронизировал. Ручные правки в кластере откатываются (`selfHeal: true`).

## Решения

- **Traefik отключён**, вместо него ingress-nginx: тот же контроллер, что в большинстве managed-кластеров, конфиги переносятся без изменений.
- **Values отдельно от чартов** через multi-source Applications: версия чарта и настройки меняются независимо.
- **Алерты** идут в Telegram через [alertmanager-telegram-relay](https://github.com/Sakuratix/alertmanager-telegram-relay).
- **Проверка в CI**: все манифесты прогоняются через [kubeconform](https://github.com/yannh/kubeconform) со схемами CRD из [datreeio/CRDs-catalog](https://github.com/datreeio/CRDs-catalog).
