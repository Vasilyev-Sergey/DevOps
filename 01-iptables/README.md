# Реализовать фаервол на iptables, в котором будет разделение на цепочки(chain) по указанным критериям:

* цепочка для адресов, которым разрешено все (все порты)
* цепочка для адресов серверов баз данных и контейнеров с приложением, которым разрешено все
* цепочка, в которую будут заноситься адреса пользователей, которым нужен доступ по требованию. Им также разрешено все
* цепочка, в которую будут заноситься адреса пользователей с временным доступом, им разрешены только определенные порты
* цепочка, в которую заносятся порты, смотрящие в мир
  Остальной траффик блокируем и все что блокируем - логируем. Для каждой цепочки организовать свой файл лога. В выводе iptables -L каждый добавленный адрес должен быть подписан именем.
