# Workflow

A simple framework for processing.

The framework helps to define a complex processing of one “work item” that can be executed within an `Execution` environment. For each work item a separate `Execution` instance has to be created. If more than one work item is to be processed, then more than one `Execution` instance has to be used.

Additionally, loggers are used that outlive the creation of executions. Part of an execution is always a logger; usually the same logger is used for many executions. There is the implementation of a logger that just combines a number of other loggers that are given in its initialisation. You can also use an additional “crash logger” to ensure that selected logging entries get logged also in the case of a crash. See the section on logging for more information.

The framework can also handle asynchronous calls (see the section about working in asynchronous contexts) and as such fits very well into asynchronous settings like web services where you might e.g. get data from a database in an asynchronous way. Logging presents itself as a synchronous service, but you can easily extend `ConcurrentLogger` to organise concurrent logging under the hood. Some convenient loggers are predefined, some of them indeed extending `ConcurrentLogger`. (See their implementation to understand how to define your own logger.)

This framework relies in part on some easy conventions[^1] to make the logic of your processing more intelligible. At its core it is just “functions calling functions” and such gives you at once perfomance, flexibility, and type safety. (So it does not define a process logic in a “traditional” way, which would not allow such flexibility.)

[^1]: One can remove the term “convention” entirely from the description and say that the processing is controlled by calls to the `effectuate` and `force` methods with unique identifiers, which implements a process management. The conventions are used for clarity and are not decisive from a conceptual point of view.

This documentation contains some motivation. For a quick start, there is a tutorial below. For more details, you might look at the conventions (between horizontal rules) given further below and look at some code samples. A complete example is given as [SwiftWorkflowExampleProgram](https://github.com/stefanspringer1/SwiftWorkflowExampleProgram), using some steps defined in the library [SwiftWorkflowExampleLibrary](https://github.com/stefanspringer1/SwiftWorkflowExampleLibrary). The common data format being read at each “entry point” (job) in that example (which could be e.g. an XML document in other cases) is defined in [SwiftWorkflowExampleData](https://github.com/stefanspringer1/SwiftWorkflowExampleData). Code from that example (maybe in modified form) is used below.

[WorkflowInVapor](https://github.com/stefanspringer1/WorkflowInVapor) is a simple [Vapor](https://vapor.codes) app using a workflow.

The API documentation is to be created by using DocC, e.g. in Xcode via „Product“ / „Build Documentation“.[^2]

[^2]: But note that in the current state of DocC, that documentation will not document any extensions, see the Swift issue [SR-15410](https://github.com/apple/swift-docc/issues/210).

The `import Workflow` and other imports are being dropped in the code samples.

## How to add the package to your project

The package is to be inlcuded as follows in another package: in `Package.swift` add:

The top-level dependency:

```Swift
.package(url: "https://github.com/stefanspringer1/SwiftWorkflow", from: "...put the minimal version number here..."),
```

(You might reference an exact version by defining e.g. `.exact("0.0.1")` instead.)

As dependency of your product:

```Swift
.product(name: "Workflow", package: "SwiftWorkflow"),
```

As long as the [concise magic file name](https://github.com/apple/swift-evolution/blob/main/proposals/0274-magic-file.md) is not yet the default for your Swift version, you need to enable it via the follwoing [upcoming feature flag](https://www.swift.org/blog/using-upcoming-feature-flags/) for your target:

```Swift
swiftSettings: [
    .enableUpcomingFeature("ConciseMagicFile"),
]
```

The Workflow package will be then usable in a Swift file after adding the following import:

```Swift
import Workflow
```

If you use the workflows of the type introduced here on macOS, at least macOS version 10.15 is required; if an essential part of your application is the use of workflows of the type introduced here, instead of using many `@available(macOS 10.15.0, *)` annotations, you might as well add the following `platforms` entry to your `Package.swift` file[^3]:

```Swift
let package = Package(
    name: "MyPackage",
    platforms: [
        .macOS(.v10_15)
    ],
    ...
```

[^3]: But better do not use such a `platforms` entry when building a package that has other parts that could be independendly used on older macOS versions. On Linux or Windows, you just have to make sure to use an according Swift version.

## Step list tool

This package contains the executable target `StepsFromLog` which lists the step called from a log with a log level of at least `Progress`.

Deliver the path to the log file as an argument, the result will be printed to standard output.

The step description is a "pretty print" output made from the name of the step function.

## Related packages

When you need to log via an existing `LogHandler` according to [swift-log](https://github.com/apple/swift-log), you might use the `SwiftLogger` wrapper from [SwiftLoggingBindingForWorkflow](https://github.com/stefanspringer1/SwiftLoggingBindingForWorkflow).

When working with [SwiftXML](https://github.com/stefanspringer1/SwiftXML) in the context of this workflow framework, you might include the [WorkflowUtilitiesForSwiftXML](https://github.com/stefanspringer1/WorkflowUtilitiesForSwiftXML).

## Tutorial

You first need a logger. A common use case is to print to standard out and standard error, and to also log into a file:

```Swift
let logger = MultiLogger(
    PrintLogger(loggingLevel: .Info, progressLogging: true),
    try FileLogger(usingFile: "my file")
)
```

Then, for each work item that you want to process (whatever your work items might be, maybe you have only one work item so you do not need a for loop), use a new `Execution` object:

```Swift
for workItem in workItems {
    let execution = Execution(logger: logger, applicationName: "My App")
    myWork_step(during: execution, forWorkItem: workItem)
}
```

`workItem` is of any type you want (let's say, of type `WorkItem`), and the step you call (here: `myWork_step`) might have any other arguments, and the postfix `_step` is only for convention. Your step might be implemented as follows:

```Swift
func myWork_step(
    during execution: Execution,
    forWorkItem workItem: workItem
) {
    execution.effectuate(checking: StepID(crossModuleFileDesignation: #file, functionSignature: #function)) {
        
        // ... some other code...
        
        myOther_step(during: execution, forWorkItem: workItem)
        
        // ... some other code...
        
    }
}
```

`#file` should denote the [concise magic file name](https://github.com/apple/swift-evolution/blob/main/proposals/0274-magic-file.md) `<module-name>/<file-name>` (you might have to use the [upcoming feature flag](https://www.swift.org/blog/using-upcoming-feature-flags/) `ConciseMagicFile` for this, see the `Package.swift` file of this package).

I.e. you embrace the content of your function inside a `execution.effectuate` call so that the `Execution` instance can log and control the execution of your code (e.g. does not continue after a fatal error). the `StepID` instance is used as a unique identifier for your step.

_Note that in order to be able to use future enhancemants of the library, you should not have code outside this single call of `effectuate` in your function!_

Inside your step you might call other steps. In the example above, `myOther_step` has the same arguments as `myWork_step`, but in the general case, this does not have to be this way. On the contrary, our recommendation is to only give to each step the data that it really needs.

If you call `myOther_step` inside `myWork_step` as in the example above, `myOther_step` (or more precisely, the code inside it that is embraced in a `execution.effectuate` call) will not be executed if `myWork_step` has already been executed before during the same execution (of the work item). This way you can formulate prerequisites that should have been run before, but without getting the prerequisites executed multiple times. If you want to force the execution of `myOther_step` at this point, use the following code:

```Swift
execution.force {
    myOther_step(during: execution, forWorkItem: workItem)
}
```

You can also disremember what is executed with the following call:

```Swift
execution.disremember {
    myOther_step(during: execution, forWorkItem: workItem)
}
```

There are also be named optional parts that can be activated by adding an according value to the `withOptions` value in the initializer of the `Execution` instance:

```Swift
execution.optional(named: "module1:myOther_step") {
        myOther_step(during: execution, forWorkItem: workItem)
}
```

On the contrary, if you regard a step at a certain point or more generally a certain code block as something dispensable (i.e. the rest of the application does not suffer from inconsistencies if this part does not get executed), use the following code: 

```Swift
execution.dispensable(named: "module1:myOther_step") {
        myOther_step(during: execution, forWorkItem: workItem)
}
```

The part can then be deactivated by adding the according name to the `dispensingWith` value in the initializer of the `Execution` instance.

So with `execution.optional(named: ...) { ... }` you define a part that does not run in the normal case but can be activated, and with `execution.dispensable(named: ...) { ... }` you define a part that runs in the normal case but can be deactivated. It is recommended to add the module name to the part name as a prefix in both cases.

An activated option can also be dispensed with („dispensing wins“).

If your function contains `async` code (i.e. `await` is being used in the calls), use `execution.async.effectuate` instead of `execution.effectuate` or `execution.async.force` instead of `execution.force` (a step might also be an `async` function).

Call `execution.log(...)` to log a message:

```Swift
execution.log(myError, myData)
```

Such a message might be defined as follows:

```Swift
let myError = Message(
    id: "my error",
    type: .Error,
    fact: [
        .en: "this is an error with additional info \"$0\"",
    ]
)
```

The texts `$0`, `$1`, ... are being replaced by arguments (of type `String`) in their order in the call to `execution.log`.

Do not forget to close your logger at the end of your program (so all messages are e.g. written):

```Swift
try logger.close()
```

## Motivation

We think of a processing of a work item consisting of several steps, each step fullfilling a certain piece of work. We first see what basic requirements we would like to postulate for those steps, and then how we could realize that in practice.

### Requirements for the execution of steps

The steps comprising the processing might get processed in sequence, or one step contains other steps, so that step A might execute step B, C, and D.

We could make the following requirements for the organization of steps:

- A step might contain other steps, so we can organize the steps in a tree-like structure.
- Some steps might stem from other packages.
- A step might have as precondition that another step has already been executed before it can do some piece of work.
- There should be an environment accessible inside the steps which can be used for logging (or other communication).
- This environment should also have control over the execution of the steps, e.g. when there is a fatal error, no more steps should be executed.

But of course, we do not only have a tree-like structure of steps executing each-other, _somewhere_ real work has to be done. Doing real work should also be done inside a step, we do not want to invent another type of thing, so:

- In each step should be able to do real work besides calling other steps.

We would even go further:

- In each step, there should be no rules of how to mix “real work” and the calling of other steps. This should be completely flexible.

We should elaborate this last point. This mixture of the calling of steps and other code may seem suspicious to some. There are frameworks for organizing the processing which are quite strict in their structure and make a more or less strict separation between the definition of which steps are to be executed and when, and the actual code doing the real work. But seldom this matches reality (or what we want the reality to be). E.g. we might have to decide dynamically during execution which step to be processed at a certain point of the execution. This decision might be complex, so we would like to be able to use complex code to make the decision, and moreover, put the code exactly to where the call of the step is done (or not done).

We now have an idea of how we would like the steps to be organized.

In addition, the steps will operate on some data to be processed, might use some configuration data etc., so we need to be able to hand over some data to the steps, preferably in a strictly typed manner. A step might change this data or create new data and return the data as a result. And we do not want to presuppose what types the data has or how many arguments are used, a different step might have different arguments (or different types of return values).

Note that the described flexibility of the data used by each step is an important requirement for modularization. We do not want to pass around the same data types during our processing; if we did so, we could not extract a part of our processing as a separate, independant package, and we would not be very precise of what data is required for a certain step.

### Realization of steps

When programming, we have a very common concept that fullfills most of the requirements above: the concept of a _function._ But when we think of just using functions as steps, two questions immediately arise:

- How do we fullfill the missing requirements?
- How can we visually make clear in the code where a step gets executed?

So when we use functions as steps, the following requirements are missing:

- A step might have as precondition that another step has already been executed before it can do some piece of work.
- There should be an environment accessible inside the steps which can be used for logging (or other communication).
- This environment should also have control over the execution of the steps, e.g. when there is a fatal error, the execution of the steps should stop.

We will see in the next section how this is resolved. For the second question ("How can we visually make clear in the code where a step gets executed?"): We just use the convenstion that a step i.e. a function that realizes a step always has the postfix "\_step" in its name. Some people do not like relying on conventions, but in practice this convention works out pretty well.

---
**Convention**

A function representing a step has the postfix `_step` in its name.

---

## Concept

### An execution

An `Execution` has control over the steps, i.e. it can decide if a step actually executes, and it provides method for logging. It will be explained later in detail.

### Formulation of a step

To give an `Execution` control over a function representing a step, its statements are to be wrapped inside a call to `Execution.effectuate`.

---
**Convention**

A function representing a step uses a call to `Execution.effectuate` to wrap all its other statements.

---

We say that a step “gets executed” when we actually mean that the statements inside its call to `effectuate` get executed.

A step fullfilling "task a" is to be formulated as follows. In the example below, `data` is the instance of a class being changed during the execution (of cource, our steps could also return a value, and different interacting steps can have different arguments). The execution keeps track of the steps run by using _a unique identifier for each step._ An instance of `StepID` is used as such an identifier, which contains a) a designation for the file that is unique across modules (using [concise magic file name](https://github.com/apple/swift-evolution/blob/main/proposals/0274-magic-file.md)), and b) using the function signature which is unique when using only top-level functions as steps.

```Swift
func a_step(
    during execution: Execution,
    data: MyData
) {
    execution.effectuate(checking: StepID(crossModuleFileDesignation: #file, functionSignature: #function)) {
        
        print("working in step a")
        
    }
}
```

---
**Convention**

- A function representing a step is a top-level function.
- Use the function signature available via `"\(#function)@\(#file)"` as the identifier in the call of the `effectuate` method.

---

Let us see how we call the step `a_step` inside another step `b_step`:

```Swift
func b_step(
    during execution: Execution,
    data: MyData
) {
    execution.effectuate(checking: StepID(crossModuleFileDesignation: #file, functionSignature: #function)) {
        
        a_step(during: execution, data: data)
        
        print("working in step b")
    }
}
```

Here, the call to `a_step` can be seen as the formulation of a requirement for the work done by `b_step`.

Let us take another step `c_step` which first calls `a_step`, and then `b_step`:

```Swift
func c_step(
    during execution: Execution,
    data: MyData
) {
    execution.effectuate(checking: StepID(crossModuleFileDesignation: #file, functionSignature: #function)) {
        
       a_step(during: execution, data: data)
       b_step(during: execution, data: data)
        
       print("working in step c")
        
    }
}
```

Again, `a_step` and `b_step` can be seen here as requirements for the work done by `c_step`.

When using `c_step`, inside `b_step` the step `a_step` is _not_ being executed, because `a_step` has already been excuted at that time. By default it is assumed that a step does some manipulation of the data, and calling a step  says "I want those manipulation done at this point". This is very common in complex processing scenarios and having this behaviour ensures that a step can be called in isolation and not just as part as a fixed, large processing pipeline, because it formulates itself which prerequisites it needs.[^4]

[^4]: Note that a bad formulation of your logic can get you in trouble with the order of the steps: If `a_step` should be executed before `b_step` and not after it, and when calling `c_step`, `b_step` has already been executed but not `a_step` (so, other than in our example, `a_step` is not given as a requirement for `b_step`), you will get the wrong order of execution. In practice, we never encountered such a problem.

---
**Convention**

Requirements for a step are formulated by just calling the accordings steps (i.e. the steps that fullfill the requirements) inside the step. (Those steps will not run again if they already have been run.)

---


But sometimes a certain other step is needed just before a certain point in the processing, no matter if it already has been run before. In that case, you can use the `force` method of the execution:

```Swift
func b_step(
    during execution: Execution,
    data: MyData
) {
    execution.effectuate(checking: StepID(crossModuleFileDesignation: #file, functionSignature: #function)) {
        
        execution.force {
            a_step(during: execution, data: data)
        }
        
        print("working in step b")
        
    }
}
```

Now `a_step` always runs inside `b_step` (if `b_step` gets executed).

Note that any sub-steps of a forced step are _not_ automatically forced. But you can pass a forced execution onto a sub-step by calling it inside `inheritForced`:

```Swift
func b_step(
    during execution: Execution,
    data: MyData
) {
    execution.effectuate(checking: StepID(crossModuleFileDesignation: #file, functionSignature: #function)) {
        
        execution.inheritForced {
            // this execution of a_step is forced if the current execution of b_step has been forced:
            a_step(during: execution, data: data)
        }
        
        print("working in step b")
        
    }
}
```

---
**Convention**

Use the `Execution.force` method if a certain step has to be run at a certain point no matter if it already has been run before.

---

### How to return values

If the step is to return a value, this must to be an optional one:

```Swift
func my_step(
    during execution: Execution,
    data: MyData
) -> String? {
    execution.effectuate(checking: StepID(crossModuleFileDesignation: #file, functionSignature: #function)) {
        ...
        return "my result"
        ...
    }
}
```

Note that the `effectuate` method returns the according value, so there is no need to set up any variable outside the `effectuate` call.

_The optionality must stem from the fact that the execution might be effectuated or not._ If the code within the `effectuate` call is itself is meant to return an optional value, this has to be done e.g. via the `Result` struct:

```Swift
func my_step(
    during execution: Execution,
    data: MyData
) -> Result<String, ErrorWithDescription>? {
    execution.effectuate(checking: StepID(crossModuleFileDesignation: #file, functionSignature: #function)) {
        ...
        var value: String?
        ...
        if let value {
            return .success(value)
        } else {
            return .failure(ErrorWithDescription("the value is not set")))
        }
}
```

You can then check if (in the example) a `String` value is returned by e.g.:

```Swift
if case .success(let text) = my_step(during: execution:, data: MyData) {
    print(text)
}
```

### Outsourcing functionality into a new package

The tree-like pattern of steps that you are able to use in a workflow is a natural starting point to outsource some functionality of your workflow into an external package.

### Organisation of the code in the files

We think it a a sensible thing to use one file for one step. Together with the step data (which includes the error messages, see below), maybe an according library function, or a job function (see below), this "fits" very well a file in many case.

We also prefer to use folders with scripts according to the calling structure as far as possible, and we like to use a prefix `_external_` for the names of folders and source files if the contained steps actually call external steps i.e. library functions as described above.

### Limitations

This approach has as limitation that a library function is a kind of isolated step: From the view of a library function being called, there are no step functions that already have been run. In some cases, this limitation might lead to preparation steps done sevaral times, or certain prerequisites have to be formulated in the documentation of the library function and the according measures then taken in the wrapper of the library function. Conversely, to the outside not all that has been done by the library function might be taken into account in subsequent steps.

In practice we think that this limitation is not a severe one, because usually a library function is a quite encapsulated unit that applies, so to speak, some collected knowledge to a certain problem field and _should not need to know much_ about the outside.

### Jobs

Steps as described should be flexible enough for the definition of a sequence of processing. But in some circumstances you might want to distinguish between a step that reads (and maybe writes) the data that you would like to process, and the steps in between that processes that data. A step that reads (and maybe writes) the data would then be the starting point for a processing. We call such a step a “job” and give its name the postfix `_job` instead of `_step`:

```Swift
func helloAndBye_job(
    during execution: Execution,
    file: URL
) {
    
    // get the data:
    guard let data = readData_step(during: execution, file: file) else { return }
    
    // start the processing of the data:
    helloAndBye_step(during: execution, data: data)
}
```

So a job is a kind of step that can be called on top-level i.e. not from within another step.

It is a good practice to always create a job for each step even if such a job is not planned for the final product, so one can test each step separately by calling the according job.

### Using an execution just for logging

You might use an `Execution` instance just to make the logging streamlined.

### Jobs as starting point for the same kind of data

Let us suppose you have jobs that all share the same arguments and the same data (i.e. the same return values) and you would like to decide by a string value (which could be the value of a command line argument) which job to start.

So a job looks e.g. as follows:

```Swift
typealias Job = (
    Execution,
    URL
) -> ()
```

In this case we like to use a "job registry" as follows (for the step data, see the section below):

```Swift
var jobRegistry: [String:(Job?,StepData)] = [
    "hello-and-bye": JobAndData(job: helloAndBye_job, stepData: HelloAndBye_stepData.instance),
    // ...
]
```

The step data – more on that in the next section – is part of the job registry so that all possible messages can be automatically collected by a `StepDataCollector`, which is great for documentation. (This is why the job in the registry is optional, so you can have messages not related to a step, but nevertheless formulated inside a `StepData`, be registered here under an abstract job name.)

The resolving of a job name and the call of the appropriate job is then done as follows:

```Swift
    if let jobFunction = jobRegistry[job]?.job {
        
        let applicationName = "SwiftWorkflowExampleProgram"
        let logger = PrintLogger()
        let execution = Execution(logger: logger, applicationName: applicationName, showSteps: true)
        
        jobFunction(
            execution,
            URL(fileURLWithPath: path)
        )
    }
    else {
        // error...
    }
```

### Spare usage of step arguments

Generally, a step should only get as data what it really needs in its arguments. E.g. handling over a big collection of configuration data might ease the formulation of the steps, but being more explicit here - i.e. handling over just the parts of the configuration data that the step needs – makes the usage of the data much more transparent and modularization (i.e. the extraction of some step into a separate, independant package) easy.

### Step data

Each step should have an instance of `StepData` in its script with:

- a short description of the step, and
- a collection of message that can be used when logging.

When logging, only the messages declared in the step data should be used.

A message is a collection of texts with the language as keys, so you can define
the message text in different languages. The message also defines the type of the
message, e.g. if it informs about the progress or about a fatal error.

The message types (of type `MessageType`, e.g. `Info` or `Warning`) have a strict order, so you can choose the minimal level for a message to be logged. But the message type `Progress` is special: if progress should be logged is defined by an additional parameter.

See the example project for more details.

### Working in asynchronous contexts

A step might also be asynchronous, i.e. the caller might get suspended. Let's suppose that for some reason `bye_step` from above is async (maybe we are building a web application and `bye_step` has to fetch data from a database):

```Swift
func bye_step(
    during execution: Execution,
    data: MyData
) async {
    ...
```

Then `helloAndBye_step` which calls `bye_step` has to use `execution.async.effectuate` instead of just `execution.effectuate`:

```Swift
func helloAndBye_step(
    during execution: Execution,
    data: MyData
) async {
    await execution.async.effectuate(checking: StepID(crossModuleFileDesignation: #file, functionSignature: #function)) { {
        
        execution.log(stepData.sayingHelloAndBye, data.value)
        
        trim_step(during: execution, data: data)
        hello_external_step(during: execution, data: data)
        await bye_step(during: execution, data: data)
        
    }
}
```

See how the `async` keyword tells us exactly where work might get suspended. This is one of the reasons why we took care that logging does not present itself asynchronous, although we can have loggers that can be accessed concurrently: Having `async` loggers would lead to ubiquitous `async` functions (a function that calls an `async` function has itself to be an `async` function), and each `async` function has to be called with `await`. But an `await` statement should express “this piece of work could be suspended, and for good reasons”.[^6]

[^6]: Using actors (with `async` methods) as loggers would also have _advantages_, e.g. making it easy to ensure that the actual logging has happened before continuing.

To force an execution, use `execution.async.force` in asynchronous contexts instead of `execution.force`:

```Swift
await execution.async.force {
    await bye_step(during: execution, data: data)
}
```

In an asynchronous setting, consider setting the logging level e.g. for a `PrintLogger` to `Warning` or `Iteration`.

Use `forEachAsync` from [SwiftUtilities](https://github.com/stefanspringer1/SwiftUtilities) instead of `forEach` when iterating through a sequence in an asynchronous context.

### Logging

Errors thrown should always be handled and the logging mechanism used.

An execution can handle logging to a `Logger` (a protocol) instance. Several logger
implementations are included, among others a logger that can be used to distribute
logging events to several other loggers (so actually several loggers are used at once).

The same logger instances clearly should be used for all `Execution` instances. So you do not create loggers for each execution, but you create the loggers once and use them in each creation of an execution.

See the example project for more details.

Note that we use a set of **message types** different from the one in the [Swift logging mechanism](https://apple.github.io/swift-log/docs/current/Logging/Structs/Logger.html): E.g. we differentiate a “fatal” error when the processing of a work item cannot continue from a “deadly” error when the processing as a whole (not only for a certain work item) cannot continue. And we have a message type “Iteration” that should be used to inform about the start and the stop of the processing of a work item; we judge this information as being more important as warnings, therefore this separate message type.[^7]

[^7]: But see the last section on possible future directions for a binding.

The usual logging (when you are e.g. extending `ConcurrentLogger` because you want to do logging in a concurrent context) is something that is designed not to get into the way of your processing and is meant to be efficient, i.e. no `await` keyword is necessary, events might be actually logged a little bit later, and when there is a crash, logging entries might get lost.[^8] The loss of logging entries in the case of a crash is less severe if you can reproduce the problem, but then you need enough information about how to reproduce it, e.g. you then want to know which work item has been worked on. So you might add a **“crash logger”** in the argument `crashLogger` when initializing an `Execution`, and to implement one, you might want to extend the `ConcurrentCrashLogger`. When logging with a `ConcurrentCrashLogger` the caller automatically waits until the logging of the log entry has been done, so when after the logging the application crashes, you still have this log entry. (Extensive logging to such a crash logger should be avoided, as this slows down your application.) The `FileCrashLogger` is an extension of `ConcurrentCrashLogger` to write such information into a file. You additionally direct a log entry to the crash logger of an `Execution` by setting `addCrashInfo: true` in the call to `Execution.log(...)`. For debugging purposes, you can also set `alwaysAddCrashInfo: true` in the initialisation of the `Execution`, every log entry is then addionally directed to the crash logger.

[^8]: Of course, you should always log when the processing of a work item has been finished, else you might not determine a crash that happened. If you have a batch processing and remove the crash log after completion of your work, the existing of a crash file can indicate a crash.

### Appeasing log entries

The error class is used when logging represents the point of view of the step or package. This might not coincide with the point of view of the whole application. Example: It is fatal for an image library if the desired image cannot be generated, but for the overall process it may only be a non-fatal error, an image is then simply missing.

So the caller can execute the according code in `execution.appease { … }`. In side this code, any error worse than `Error` is set to `Error`. Instead if this default `Error`, you can also specify the message type to which you want to appease via `execution.appease(to: …) { … }`. The original error type is preserved as field `originalType` of the logging event.

So using an "external" step would actually be formulated as follows in most cases:

```Swift
func hello_external_step(
    during execution: Execution,
    data: MyData
) {
    execution.effectuate(checking: StepID(crossModuleFileDesignation: #file, functionSignature: #function)) {
    
        execution.appease {
            hello_lib(during: execution, data: data)
        }
        
    }
}
```

### Logging to an execution in a concurrent context

In a concurrent context, use `execution.parallel` to create a copy of an `execution`.

Example:

```Swift
dispatchGroup.enter()
dispatchQueue.async {
    semaphore.wait()
    let parallelExecution = execution.parallel
    myStep(
        during: parallelExecution,
        theDate: theData
    )
    ...remeber parallelExecution.worstMessageType...
    semaphore.signal()
    disptachGroup.leave()
}
```

You need to update the worst message type after the parallel runs:

```Swift
for ... in ... {
    execution.updateWorstMessageType(with: max(..., execution.worstMessageType))
}
```

Note that the parallel steps are not registered in the execution database. But the above code migth be part of anther step not executed in parallel, and that one will then be registered.

### Binding to the Swift logging mechanism

Our logging has e.g. different message levels (or log levels) than the [Swift logging mechanism](https://apple.github.io/swift-log/docs/current/Logging/Structs/Logger.html), see the documentation of the APIs. A binding is provided in the package [SwiftLoggingBindingForWorkflow](https://github.com/stefanspringer1/SwiftLoggingBindingForWorkflow).

### Future directions

The following features might be added in the future:

- A pause/stop mechanism.
- A mechanism for _pulling_ progress information (an according `Logger` implementation should suffice).
- Customized tooling for easy parallel processing of several work items.
- Tooling for giving an entry point for different types of data and using several job registries (each for one types of data) as a way to combine sevaral application under one umbrella.
- Making parellel execution easier to handle.
