[InjectionIII](https://github.com/johnno1962/InjectionIII)分支。原项目通过在你的App中接收`Notification`或实现`injected`方法来更新界面。这个分支去掉了这部分代码，当你的代码保存时，自动查找当前显示的`ViewController`，并重新加载，你的项目不需要添加任何代码。
主要服务[DeclareLayoutSwift](https://github.com/huangzhouhong/DeclareLayoutSwift)，暂不考虑支持Storyboard。其他使用手写UI代码的情况，应当也适用。

使用流程
---

白色部分是Injection做的
![Injection](https://upload-images.jianshu.io/upload_images/6719795-c87912f8f9e14b21.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)
