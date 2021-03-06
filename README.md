手写代码不能所见即所得，每次细微修改都需要重新生成和运行才能看到效果。   
为了弥补这一缺陷，可以只编译修改后的文件，并注入到运行中的App，整个过程可以在一秒钟内完成，从而提高开发效率。  
[InjectionIII](https://github.com/johnno1962/InjectionIII)就有这样的功能。   
我创建这个分支，使你的项目不需要做任何修改就可以实现上述功能，只要保存代码文件，即可实时看到效果。  

原项目通过在你的App中接收`Notification`或实现`injected`方法来更新界面。这个分支去掉了这部分代码，当你的代码保存时，自动查找当前显示的`ViewController`，并重新加载，你的项目不需要添加任何代码。   
主要服务[DeclareLayoutSwift](https://github.com/huangzhouhong/DeclareLayoutSwift)，暂不考虑支持Storyboard。其他使用手写UI代码的情况，应当也适用。

使用流程
---

白色部分是Injection做的

![Injection](https://upload-images.jianshu.io/upload_images/6719795-5b9ec489bf57d1a9.png?imageMogr2/auto-orient/strip%7CimageView2/2/w/1240)

