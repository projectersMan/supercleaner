# 本批界面核对（0.2.38 / 71）

范围为用户要求的App管理误导状态与首次进入图标逐行替换。没有运行自动测试套件；release编译、双语1013条检查、逐处diff及原生App界面核对通过。已有图标回退契约脚本保留，未扩大此前其他定向测试的授权。

设置和扫描前窗口：App管理显示macOS confirms access when you uninstall an app，无Not verified/Available/需要授权徽标；FDA仍为Available，不申请新授权。实际卸载与系统保护未改动，不通过试删验证权限。

图标：原始状态为nil后task赋值，首帧占位；修正后直接从同一个同步缓存构造Image，无额外预加载服务。实际只读扫描得到94个应用，首次打开可卸载页显示22项，可见Microsoft/Otty/RepairApp图标完整。没有逐帧录屏测量；不宣称首次系统解析零成本。

包核对见[package-verification.txt](package-verification.txt)。installed-before.requirement保留更新前实际App身份要求，用其验证新包兼容；未记录或分发私钥。App已覆盖固定安装路径，镜像已卸载、临时夹具清理，未执行删除或提交。
