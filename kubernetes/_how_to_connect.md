# Подключение к тестовому кластеру (временный стенд для прогонов)

> Кластер живёт только на время разработки курса; после приёмки удаляется.

```bash
KCFG=~/opencode/dbt-data-modelling/kubernetes/kubeconfig_87aa2491-f136-45db-9bef-ab3bc55d90b6.yaml
kubectl --kubeconfig $KCFG get nodes
```

## Параметры (аудит 2026-10-31)

- Провайдер: Beget Cloud · ID кластера `a54281` · 1 узел · k8s v1.35.7 · роль `super-admin`
- Ресурсы: **16 CPU / 31.4 GiB RAM** (allocatable 15.5 / 30.5) · ~76 GiB диск · лимит 250 pod
- Узел: `a54281-client-b613bc-c96zr-qsdnf` · внешний IP `159.194.232.211`
- ✅ AVX2 на всех ядрах (StarRocks BE работает, L16 не повторяется)
- ✅ metrics-server (`kubectl top`) — замеры cpu/ram для Stage 3
- ❌ StorageClass/CSI нет → перед деплоем поставить local-path-provisioner
- ❌ LoadBalancer не получает EXTERNAL-IP → сервисы открывать NodePort'ами на 159.194.232.211

## Назначение

Только прогоны/тесты (полный `make build` ≥32 ГБ, Stage 2h/3/5 плана
`guide/cource-improve/todo_cource_dev.md`). Разработка моделей — на локальном стенде.
