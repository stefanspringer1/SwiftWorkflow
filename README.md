# Workflow

A simple framework for processing.

The framework helps to define a complex processing of one “work item” that can be executed within an `Execution` environment. For each work item a separate `Execution` instance has to be created. If more than one work item is to be processed, then more than one `Execution` instance has to be used.

Additionally, loggers are used that outlive the creation of executions. Part of an execution is always a logger; usually the same logger is used for many executions. A logger can combine several other loggers.

The framework uses asynchronuous calls and as such fits very well into asynchronuous settings like web services. Without suspension happening, those calls are about as fast as synchronuous calls, so the framework can be also used for simple straight-forward processing in the command line. Logging is also asynchronuous, but there is an easy way to intermediately present synchronuous logging to a block of code.

This framework relies in part on some easy conventions to make the logic of your processing more intelligible. At its core it is just “functions calling functions” and such gives you at once perfomance, flexibility, and type safety.[^1] So it does not define a process logic in a „traditional“ way, which would not allow such flexibility.

[^1]: One can remove the term “convention” entirely from the description and say that the processing is controlled by calls to the `effectuate` and `force` methods with an appropriate ID, which implements a process management. The conventions are used for clarity and are not decisive from a conceptual point of view.

For (parallel) processing of several work items, [Swift Async Algorithms](https://github.com/apple/swift-async-algorithms) should provide easy solutions, but we might add some customized tooling in the future. See the section on future directions at the end about what else might be added in the future.

For a quick start, just see the conventions (between horizontal rules) given below and look at some code samples. A complete example is given as [SwiftWorkflowExampleProgram](https://github.com/stefanspringer1/SwiftWorkflowExampleProgram), using some steps defined in the library [SwiftWorkflowExampleLibrary](https://github.com/stefanspringer1/SwiftWorkflowExampleLibrary). The common data format being read at each “entry point” (job) in that example (which could be e.g. an XML document in other cases) is defined in [SwiftWorkflowExampleData](https://github.com/stefanspringer1/SwiftWorkflowExampleData).

The API documentation is to be created by using DocC, e.g. in Xcode via „Product“ / „Build Documentation“.

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

It will be then usable in a Swift file after adding the following import:

```Swift
import Workflow
```

## Motivation

We think of a process consisting of several steps, each step fullfilling a certain piece of work. We first see what basic requirements we would like to postulate for those steps, and then how we could realize that in practice. Of course, some more important points will then be made.

### Requirements for the execution of steps

The steps comprising the processing might get processed in sequence, or one step contains other steps, so that step A might execute step B, C, and D.

We could make the following requirements for the organization of steps:

- A step might contain other steps, so we can organize the steps in a tree-like structure.
- Some steps might stem from other packages.
- A step might have as precondition that another step has already been executed before it can do some piece of work.
- There should be an environment accessible inside the steps which can be used for logging (or other communication).
- This environment should also have control over the execution of the steps, e.g. when there is a fatal error, the execution of the steps should stop.

But of course, we do not only have a tree-like structure of steps executing each-other, _somewhere_ real work has to be done. Doing real work should also be done inside a step, we do not want to invent another type of thing, so:

- In each step should be able to do real work besides calling other steps.

We would even go further:

- In each step, there should be no rules of how to mix “real work” and the calling of other steps. This should be completely flexible.

We should elaborate this last point. This mixture of the calling of steps and other code may seem suspicious to some. There are frameworks for organizing the processing which are quite strict in their structure and make a more or less strict separation between the definition of which steps are to be executing and when, and the actual code doing the real work. But seldom this matches reality (or what we want the reality to be). E.g. we might have to decide dynamically during execution which step to be processed at a certain point of the execution. This decision might be complex, so we would like to be able to use complex code to make the decision, and moreover, put the code exactly to where the call of the step is done (or not done).

We now have an idea of how we would like the steps to be organized.

In addition, the steps will operate on some data to be processed, might use some configuration data etc., so we need to be able to hand over some data to the steps, preferably in a strictly typed manner. A step might change this data or create new data and returns the data as a result. And we do not want to presuppose what types the data has or how many arguments are used.

### Realization of steps

When programming, we have a very common and thing that fullfills most of the requirements above: _a function._ But when we think of just using functions as steps, two questions immediately arise:

- How do we fullfill the missing requirements?
- How can we visually make clear in the code where a step gets executed?

So when we use functions as steps, the following requirements are missing:

- A step might have as precondition that another step has already been executed before it can do some piece of work.
- There should be an environment accessible inside the steps which can be used for logging (or other communication).
- This environment should also have control over the execution of the steps, e.g. when there is a fatal error, the execution of the steps should stop.

We will see in the next section how this is resolved. For the second question ("How can we visually make clear in the code where a step gets executed?"): The solution to this is simple but might somehow dissapointing to some: We just use the convenstion that a step i.e. a function that realizes a step always has the postfix "\_step" in its name.  Some people do not like relying on conventions, but in practice this works out pretty well.

---
**Convention**

A function representing a step has the postfix `_step` in its name.

---

## Concept

### An execution

An `Execution` has control over the steps, i.e. it can decide if a step actually executes, and it provides method for logging. It will be explained later in detail.

### Formulation of a step

A step fullfilling "task a" is to be formulated as follows. Just as an example, `data` is here is the instance of a class being changed during the execution (of cource, our steps could also return a value etc.). An `ExecutionDatabase` keeps track of the steps run (we have to use it separatelty from the `Execution` instance because the `ExecutionDatabase` has to be set for each Swift package separately; more on that later). The `ExecutionDatabase` instance keeps track of the functions by their function signature (name and argument names), therefore all step function _have to be top-level function_ so that the function names are unambiguous. An `ExecutionDatabase` must not be shared between several `Excution` instances.

---
**Convention**

A function representing a step is a top-level function.

---

```Swift
func a_step(
    during execution: Execution,
    usingExecutionDatabase executionDatabase: ExecutionDatabase,
    data: MyData
) async {
    await execution.effectuate(executionDatabase, #function) {
        
        print("working in step a")
        
    }
}
```

The call of the `effectuate` method of the execution, which should contain all other instructions inside the step function, is (besides the naming scheme for steps) the second convention regarding steps. We say that `a_step` gets executed when we actually mean that its content inside its `effectuate` statement gets executed. It is the `effectuate` method that controls the execution of the steps.

---
**Convention**

A function representing a step uses a call to `Execution.effectuate` to wrap all its other statements. 

---

Let us see how we call the step `a_step` inside another step `b_step`:

```Swift
func b_step(
    during execution: Execution,
    usingExecutionDatabase executionDatabase: ExecutionDatabase,
    data: MyData
) async {
    await execution.effectuate(executionDatabase, #function) {
        
        await a_step(during: execution, usingExecutionDatabase: executionDatabase, data: data)
        
        print("working in step b")
    }
}
```

Let us take another step `c_step` which first calls `a_step`, and then `b_step`:

```Swift
func c_step(
    during execution: Execution,
    usingExecutionDatabase executionDatabase: ExecutionDatabase,
    data: MyData
) async {
    await execution.effectuate(executionDatabase, #function) {
        
       await a_step(during: execution, usingExecutionDatabase: executionDatabase, data: data)
       await b_step(during: execution, usingExecutionDatabase: executionDatabase, data: data)
        
        print("working in step c")
        
    }
}
```

Inside `b_step`, the step `a_step` is _not_ being executed, because `a_step` has already been excuted at that time. By default it is assumed that a step does some manipulation of the data, and calling a step  says "I want those manipulation done at this point". This is very common in complex processing scenarios and having this behaviour ensures that a step can be called in isolation and not just as part as a fixed, large processing pipeline, because it formulates itself which prerequisites it needs.

But sometimes a certain other step is needed just before a certain point in the processing, no matter if it already has been run before. In that case, you can use the `force` method of the execution:

```Swift
func b_step(
    during execution: Execution,
    usingExecutionDatabase executionDatabase: ExecutionDatabase,
    data: MyData
) async {
    await execution.effectuate(executionDatabase, #function) {
        
        await execution.force {
            await a_step(during: execution, usingExecutionDatabase: executionDatabase, data: data)
        }
        
        print("working in step b")
        
    }
}
```

Now `a_step` always runs inside `b_step` (if `b_step` gets executed).

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
) async {
    await hello_step(during: execution, usingExecutionDatabase: ExecutionDatabase(), data: data)
}

func hello_step(
    during execution: Execution,
    usingExecutionDatabase executionDatabase: ExecutionDatabase,
    data: MyData
) async {
    await execution.effectuate(executionDatabase, #function) {
        
        await execution.log(stepData.sayingHello, data.value)
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
) async {
    await execution.effectuate(executionDatabase, #function) {
        
        await hello_lib(during: execution, data: data)
        
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

The recursive patterm of steps that you are able to use in a workflow is a natural[^2] starting point to outsource some functionality of your workflow into an external package.

[^2]: The term “natural” is from category theory where it decribes in a formal way that when you transform a structure to a certain other equivalent structure, you do not have to make a decision at any point.

### Organisation of the code in the files

We think it a a sensible thing to use one file for one step. Together with the step data (which includes the error messages, see below), maybe an according library function, or a job function (see below), this "fits" very well a file in many case.

We also prefer to use folders with scripts according to the calling structure as far as possible.

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
) async {
    
    // get the data:
    guard let data = await readData_step(during: execution, usingExecutionDatabase: executionDatabase, file: file) else { return }
    
    // start the processing of the data:
    await helloAndBye_step(during: execution, usingExecutionDatabase: executionDatabase, data: data)
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
) async -> ()
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
        
        let applicationPrefix = "SwiftWorkflowExampleProgram"
        let logger = PrintLogger()
        let execution = Execution(logger: logger, applicationPrefix: applicationPrefix, showSteps: true)
        
        await jobFunction(
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

Generally, a step should only get as data what it really needs in its arguments. E.g. handling over a big collection of configuration data might ease the formulation of the steps, but being more explicit here - i.e. handling over just the parts of the configuration data that the step needs – makes the usage of the data much more transparent.

### Step data

Each step should have an instance of `StepData` in its script with:

- a short description of the step, and
- a collection of message that can be used when logging.

When logging, only the messages declared in the step data should be used.

A message is a collection of texts with the language as keys, so you can define
the message text in different languages. The message also defines the type of the
message, e.g. if it informs about the progress or about a fatal error.

See the example project for more details.

### Logging

Errors thrown should always be handled and the logging mechanism used.

An execution can handle logging to a `Logger` (a protocol) instance. Several logger
implementations are included, among others a logger that can be used to distribute
logging events to several other loggers (so actually several loggers are used at once).

The same logger instances clearly should be used for all `Execution` instances. So you do not create loggers for each execution, but you create the loggers once and use them in each creation of an execution.

If you need logging in a synchronous subcontext, use a call of `collectingErrors(forExecution:block:)` to be able to use a `SynchronousCollectingLogger` within the its closure argument:

```Swift
await collectingErrors(forExecution: execution) { logger in
    // ...do something, use the SynchronousCollectingLogger "logger" 
}
```

See the example project for more details.

### Working in asynchronous contexts

In an asynchronuous setting, consider setting the logging level e.g. for a `PrintLogger` to `Warning` or `Execution`.

Use `forEachAsync` from [SwiftUtilities](https://github.com/stefanspringer1/SwiftUtilities) instead of `forEach` when iterating through a sequence in an asynchronuous context.

### Future directions

The following features might be added in the future:

- A pause/stop mechanism.
- A mechanism for _pulling_ progress information (an according `Logger` implementation should suffice).
- Customized tooling for easy parallel processing of several work items (using [Swift Async Algorithms](https://github.com/apple/swift-async-algorithms)).
- Tooling for giving an entry point for different types of data and using several job registries (each for one types of data) as a way to combine sevaral application under one umbrella.
- A binding to the [Swift logging mechanism](https://apple.github.io/swift-log/docs/current/Logging/Structs/Logger.html).
