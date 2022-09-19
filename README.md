# Workflow

A simple framework for processing.

The framework helps to define a complex processing of one “work item” that can be executed within an `Execution` environment. For each work item a separate `Execution` instance has to be created. If more than one work item is to be processed, then more than one `Execution` instance has to be used.

Additionally, loggers are used that outlive the creation of executions. Part of an execution is always a logger; usually the same logger is used for many executions. There is the implementation of a logger that just combines a number of other loggers that are given in its initialisation. You can also use an additional “crash logger” to ensure that selected logging entries get logged also in the case of a crash. See the section on logging for more information.

The framework can also handle asynchronous calls (see the section about working in asynchronous contexts) and as such fits very well into asynchronous settings like web services where you might e.g. get data from a database in an asynchronous way. Logging presents itself as a synchronous service, but you can easily extend `ConcurrentLogger` to organise concurrent logging under the hood. Some convenient loggers are predefined, some of them indeed extending `ConcurrentLogger`. (See their implementation to understand how to define your own logger.)

This framework relies in part on some easy conventions[^1] to make the logic of your processing more intelligible. At its core it is just “functions calling functions” and such gives you at once perfomance, flexibility, and type safety. (So it does not define a process logic in a “traditional” way, which would not allow such flexibility.)

[^1]: One can remove the term “convention” entirely from the description and say that the processing is controlled by calls to the `effectuate` and `force` methods with unique identifiers, which implements a process management. The conventions are used for clarity and are not decisive from a conceptual point of view.

For a quick start, just see the conventions (between horizontal rules) given below and look at some code samples. A complete example is given as [SwiftWorkflowExampleProgram](https://github.com/stefanspringer1/SwiftWorkflowExampleProgram), using some steps defined in the library [SwiftWorkflowExampleLibrary](https://github.com/stefanspringer1/SwiftWorkflowExampleLibrary). The common data format being read at each “entry point” (job) in that example (which could be e.g. an XML document in other cases) is defined in [SwiftWorkflowExampleData](https://github.com/stefanspringer1/SwiftWorkflowExampleData). Code from that example (maybe in modified form) is used below.

[WorkflowInVapor](https://github.com/stefanspringer1/WorkflowInVapor) is a simple [Vapor](https://vapor.codes) app using a workflow.

The API documentation is to be created by using DocC, e.g. in Xcode via „Product“ / „Build Documentation“.[^2]

[^2]: But note that in the current state of DocC, that documentation will not document any extensions, see the Swift issue [SR-15410](https://github.com/apple/swift-docc/issues/210).

The `import Workflow` and other imports are being dropped in the code samples.

## How to add the package to your project

The package is to be inlcuded as follows in another package: in `Package.swift` add:

The top-level dependency:

```Swift
.package(url: "https://github.com/stefanspringer1/SwiftWorkflowExampleLibrary", from: ...put the minimal version number here...),
```

(You might reference an exact version by defining e.g. `.exact("0.0.1")` instead.)

As dependency of your product:

```Swift
.product(name: "Workflow", package: "SwiftWorkflow"),
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

## Related packages

When you need to log via an existing `LogHandler` according to [swift-log](https://github.com/apple/swift-log), you might use the `SwiftLogger` wrapper from [SwiftLoggingBindingForWorkflow](https://github.com/stefanspringer1/SwiftLoggingBindingForWorkflow).

When working with [SwiftXML](https://github.com/stefanspringer1/SwiftXML) in the context of this workflow framework, you might include the [WorkflowUtilitiesForSwiftXML](https://github.com/stefanspringer1/WorkflowUtilitiesForSwiftXML).

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

A step fullfilling "task a" is to be formulated as follows. In the example below, `data` is the instance of a class being changed during the execution (of cource, our steps could also return a value, and different interacting steps can have different arguments). An `ExecutionDatabase` keeps track of the steps run by using _a unique identifier for each step._ This uniqueness of the identifier has to be ensured by the developer of the steps. An easy way to ensure unique identifiers is to a) using only top-level functions as steps, and b) using the function signature as the identifier. This way the identifiers are unique _inside each package_ (this is why the `ExecutionDatabase` is separated from the `Execution` instance, to be able to use a separate `ExecutionDatabase` in each package; more on packages below). The function identifier is available via the compiler directive `#function` inside the function. An `ExecutionDatabase` must not be shared between several `Excution` instances.

```Swift
func a_step(
    during execution: Execution,
    usingExecutionDatabase executionDatabase: ExecutionDatabase,
    data: MyData
) {
    execution.effectuate(executionDatabase, #function) {
        
        print("working in step a")
        
    }
}
```

---
**Convention**

- A function representing a step is a top-level function.
- Use the function signature available via `#function` as the identifier in the call of the `effectuate` method.

---

Let us see how we call the step `a_step` inside another step `b_step`:

```Swift
func b_step(
    during execution: Execution,
    usingExecutionDatabase executionDatabase: ExecutionDatabase,
    data: MyData
) {
    execution.effectuate(executionDatabase, #function) {
        
        a_step(during: execution, usingExecutionDatabase: executionDatabase, data: data)
        
        print("working in step b")
    }
}
```

Here, the call to `a_step` can be seen as the formulation of a requirement for the work done by `b_step`.

Let us take another step `c_step` which first calls `a_step`, and then `b_step`:

```Swift
func c_step(
    during execution: Execution,
    usingExecutionDatabase executionDatabase: ExecutionDatabase,
    data: MyData
) {
    execution.effectuate(executionDatabase, #function) {
        
       a_step(during: execution, usingExecutionDatabase: executionDatabase, data: data)
       b_step(during: execution, usingExecutionDatabase: executionDatabase, data: data)
        
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
    usingExecutionDatabase executionDatabase: ExecutionDatabase,
    data: MyData
) {
    execution.effectuate(executionDatabase, #function) {
        
        execution.force {
            a_step(during: execution, usingExecutionDatabase: executionDatabase, data: data)
        }
        
        print("working in step b")
        
    }
}
```

Now `a_step` always runs inside `b_step` (if `b_step` gets executed).

---
**Convention**

Use the `Execution.force` method if a certain step has to be run at a certain point no matter if it already has been run before.

---

### Working with steps in library packages

To to be able to judge if a function has already run by its function signature, the `ExecutionDatabase` instance has to be unique for each package (since the signatures of the top-level functions are only unique inside a specific package).

So we use the following convention:

---
**Convention**

A function representing a step is not public.

---

As a public interface, we use another function which creates an `ExecutionDatabase`:

```Swift
public func hello_lib(
    during execution: Execution,
    data: MyData
) {
    hello_step(during: execution, usingExecutionDatabase: ExecutionDatabase(), data: data)
}

func hello_step(
    during execution: Execution,
    usingExecutionDatabase executionDatabase: ExecutionDatabase,
    data: MyData
) {
    execution.effectuate(executionDatabase, #function) {
        
        execution.log(stepData.sayingHello, data.value)
        print("Hello \(data.value)!")
        
    }
}
```

In the package that uses such a library function, the library function should then wrapped inside a step function as follows:

```Swift
func hello_external_step(
    during execution: Execution,
    usingExecutionDatabase executionDatabase: ExecutionDatabase,
    data: MyData
) {
    execution.effectuate(executionDatabase, #function) {
        
        hello_lib(during: execution, data: data)
        
    }
}
```

The `_external` infix is there to make the call hierarchy clear in the logs.

---
**Convention**

A function representing a public interface to a step (a “library function”) has the following properties:

- it is public,
- it has the postfix `_lib` in its name,
- it does not take any `ExecutionDatabase`, but it creates one itself,
- and it should be wrapped by a step function with the same name prefix and a second prefix (i.e. infix) `_external` in the package that uses the package with the library function.

---

The tree-like pattern of steps that you are able to use in a workflow is a natural[^5] starting point to outsource some functionality of your workflow into an external package.

[^5]: The term “natural” is from category theory where it decribes in a formal way that when you transform a structure to a certain other equivalent structure, you do not have to make a decision at any point.

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
    usingExecutionDatabase executionDatabase: ExecutionDatabase,
    file: URL
) {
    
    // get the data:
    guard let data = readData_step(during: execution, usingExecutionDatabase: executionDatabase, file: file) else { return }
    
    // start the processing of the data:
    helloAndBye_step(during: execution, usingExecutionDatabase: executionDatabase, data: data)
}
```

So a job is a kind of step that can be called on top-level i.e. not from within another step.

It is a good practice to always create a job for each step even if such a job is not planned for the final product, so one can test each step separately by calling the according job.

### Using an execution just for logging

An `Execution` can also be used without an `Executiondatabase`, just for logging. E.g. at the start of a programm when we first have to decide what job to be run and for what data, we can create an `Execution` instance just to make the logging streamlined.

### Jobs as starting point for the same kind of data

Let us suppose you have jobs that all share the same arguments and the same data (i.e. the same return values) and you would like to decide by a string value (which could be the value of a command line argument) which job to start.

So a job looks e.g. as follows:

```Swift
typealias Job = (
    Execution,
    ExecutionDatabase,
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
            ExecutionDatabase(),
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

See the example project for more details.

### Working in asynchronous contexts

A step might also be asynchronous, i.e. the caller might get suspended. Let's suppose that for some reason `bye_step` from above is async (maybe we are building a web application and `bye_step` has to fetch data from a database):

```Swift
func bye_step(
    during execution: Execution,
    usingExecutionDatabase executionDatabase: ExecutionDatabase,
    data: MyData
) async {
    ...
```

Then `helloAndBye_step` which calls `bye_step` has to use `execution.async.effectuate` instead of just `execution.effectuate`:

```Swift
func helloAndBye_step(
    during execution: Execution,
    usingExecutionDatabase executionDatabase: ExecutionDatabase,
    data: MyData
) async {
    await execution.async.effectuate(executionDatabase, #function) {
        
        execution.log(stepData.sayingHelloAndBye, data.value)
        
        trim_step(during: execution, usingExecutionDatabase: executionDatabase, data: data)
        hello_external_step(during: execution, usingExecutionDatabase: executionDatabase, data: data)
        await bye_step(during: execution, usingExecutionDatabase: executionDatabase, data: data)
        
    }
}
```

See how the `async` keyword tells us exactly where work might get suspended. This is one of the reasons why we took care that logging does not present itself asynchronous, although we can have loggers that can be accessed concurrently: Having `async` loggers would lead to ubiquitous `async` functions (a function that calls an `async` function has itself to be an `async` function), and each `async` function has to be called with `await`. But an `await` statement should express “this piece of work could be suspended, and for good reasons”.[^6]

[^6]: Using actors (with `async` methods) as loggers would also have _advantages_, e.g. making it easy to ensure that the actual logging has happened before continuing.

To force an execution, use `execution.async.force` in asynchronous contexts instead of `execution.async.force`:

```Swift
await execution.async.force {
    await bye_step(during: execution, usingExecutionDatabase: executionDatabase, data: data)
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

### Binding to the Swift logging mechanism

Our logging has e.g. different message levels (or log levels) than the [Swift logging mechanism](https://apple.github.io/swift-log/docs/current/Logging/Structs/Logger.html), see the documentation of ths API. A binding is provided in the package [SwiftLoggingBindingForWorkflow](https://github.com/stefanspringer1/SwiftLoggingBindingForWorkflow).

### Future directions

The following features might be added in the future:

- A pause/stop mechanism.
- A mechanism for _pulling_ progress information (an according `Logger` implementation should suffice).
- Customized tooling for easy parallel processing of several work items.
- Tooling for giving an entry point for different types of data and using several job registries (each for one types of data) as a way to combine sevaral application under one umbrella.
