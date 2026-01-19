// UnaMentis - Sample Curriculum Seeder
// Creates sample PyTorch curriculum for testing
//
// This file provides a way to seed the Core Data store with sample curriculum data
// for testing purposes.

import Foundation
import CoreData

/// Utility to seed sample curriculum data into Core Data
public struct SampleCurriculumSeeder {

    private let persistenceController: PersistenceController

    public init(persistenceController: PersistenceController = .shared) {
        self.persistenceController = persistenceController
    }

    /// Check if sample curriculum already exists
    @MainActor
    public func hasSampleCurriculum() -> Bool {
        let request = Curriculum.fetchRequest()
        request.predicate = NSPredicate(format: "name == %@", "PyTorch Fundamentals")
        request.fetchLimit = 1

        do {
            let count = try persistenceController.viewContext.count(for: request)
            return count > 0
        } catch {
            return false
        }
    }

    /// Seed PyTorch fundamentals curriculum
    /// - Returns: The created curriculum ID
    @MainActor
    @discardableResult
    public func seedPyTorchCurriculum() throws -> UUID {
        let context = persistenceController.viewContext

        // Create curriculum
        let curriculum = Curriculum(context: context)
        let curriculumId = UUID()
        curriculum.id = curriculumId
        curriculum.name = "PyTorch Fundamentals"
        curriculum.summary = """
            A comprehensive introduction to PyTorch for deep learning. This curriculum covers \
            the essential concepts from tensors to training neural networks, using the \
            FashionMNIST dataset as a practical example.
            """
        curriculum.createdAt = Date()
        curriculum.updatedAt = Date()

        // Create topics based on official PyTorch tutorial structure
        let topics = createPyTorchTopics(context: context, curriculum: curriculum)

        // Add topics to curriculum in order
        for (index, topic) in topics.enumerated() {
            topic.orderIndex = Int32(index)
            curriculum.addToTopics(topic)
        }

        try persistenceController.save()

        return curriculumId
    }

    /// Create PyTorch tutorial topics
    private func createPyTorchTopics(context: NSManagedObjectContext, curriculum: Curriculum) -> [Topic] {
        var topics: [Topic] = []

        // Topic 1: Tensors
        let tensors = Topic(context: context)
        tensors.id = UUID()
        tensors.title = "Tensors"
        tensors.outline = """
            Tensors are a specialized data structure that are very similar to arrays and matrices. \
            In PyTorch, we use tensors to encode the inputs and outputs of a model, as well as \
            the model's parameters. This module covers tensor creation, attributes, operations, \
            and interoperability with NumPy.
            """
        tensors.objectives = [
            "Understand what tensors are and their relationship to NumPy arrays",
            "Create tensors from data, NumPy arrays, and other tensors",
            "Work with tensor attributes: shape, dtype, and device",
            "Perform tensor operations including arithmetic and matrix multiplication",
            "Move tensors between CPU and GPU",
            "Convert tensors to and from NumPy arrays"
        ]
        tensors.mastery = 0
        tensors.curriculum = curriculum
        topics.append(tensors)

        // Topic 2: Datasets and DataLoaders
        let datasets = Topic(context: context)
        datasets.id = UUID()
        datasets.title = "Datasets and DataLoaders"
        datasets.outline = """
            PyTorch provides two data primitives: torch.utils.data.DataLoader and \
            torch.utils.data.Dataset that allow you to use pre-loaded datasets as well as \
            your own data. Dataset stores the samples and their corresponding labels, and \
            DataLoader wraps an iterable around the Dataset for easy access.
            """
        datasets.objectives = [
            "Understand the Dataset and DataLoader primitives",
            "Load built-in datasets like FashionMNIST",
            "Create custom datasets by subclassing Dataset",
            "Configure DataLoader for batching, shuffling, and parallel loading",
            "Iterate over data in training loops"
        ]
        datasets.mastery = 0
        datasets.curriculum = curriculum
        topics.append(datasets)

        // Topic 3: Transforms
        let transforms = Topic(context: context)
        transforms.id = UUID()
        transforms.title = "Transforms"
        transforms.outline = """
            Data does not always come in its final processed form that is required for \
            training machine learning algorithms. We use transforms to perform some \
            manipulation of the data and make it suitable for training. This module covers \
            ToTensor, Lambda transforms, and composing multiple transforms.
            """
        transforms.objectives = [
            "Understand why data transformation is necessary",
            "Use ToTensor to convert images to tensors",
            "Apply Lambda transforms for custom transformations",
            "Compose multiple transforms into a pipeline",
            "Apply transforms to labels as well as features"
        ]
        transforms.mastery = 0
        transforms.curriculum = curriculum
        topics.append(transforms)

        // Topic 4: Build the Neural Network
        let buildModel = Topic(context: context)
        buildModel.id = UUID()
        buildModel.title = "Build the Neural Network"
        buildModel.outline = """
            Neural networks comprise of layers/modules that perform operations on data. \
            The torch.nn namespace provides all the building blocks you need to build your \
            own neural network. Every module in PyTorch subclasses the nn.Module. \
            A neural network is a module itself that consists of other modules (layers).
            """
        buildModel.objectives = [
            "Understand the nn.Module base class",
            "Define neural network layers using nn.Linear, nn.ReLU, nn.Flatten, etc.",
            "Build a complete neural network class with __init__ and forward methods",
            "Move models to GPU for accelerated computation",
            "Inspect model structure and parameters"
        ]
        buildModel.mastery = 0
        buildModel.curriculum = curriculum
        topics.append(buildModel)

        // Topic 5: Automatic Differentiation
        let autograd = Topic(context: context)
        autograd.id = UUID()
        autograd.title = "Automatic Differentiation with torch.autograd"
        autograd.outline = """
            When training neural networks, the most frequently used algorithm is \
            back propagation. In this algorithm, parameters are adjusted according to \
            the gradient of the loss function with respect to the given parameter. \
            PyTorch's autograd engine powers neural network training.
            """
        autograd.objectives = [
            "Understand computational graphs and automatic differentiation",
            "Use requires_grad to track operations for gradient computation",
            "Compute gradients using backward()",
            "Disable gradient tracking with torch.no_grad() for inference",
            "Understand gradient accumulation and when to zero gradients"
        ]
        autograd.mastery = 0
        autograd.curriculum = curriculum
        topics.append(autograd)

        // Topic 6: Optimizing Model Parameters
        let optimization = Topic(context: context)
        optimization.id = UUID()
        optimization.title = "Optimizing Model Parameters"
        optimization.outline = """
            Now that we have a model and data it's time to train, validate and test our model \
            by optimizing its parameters on our data. Training a model is an iterative process; \
            each iteration (called an epoch) the model makes predictions, calculates loss, \
            and adjusts parameters.
            """
        optimization.objectives = [
            "Set up a loss function appropriate for the task",
            "Initialize an optimizer (SGD, Adam, etc.)",
            "Implement the training loop: forward pass, loss computation, backpropagation",
            "Implement the validation/test loop",
            "Monitor training progress with loss and accuracy metrics"
        ]
        optimization.mastery = 0
        optimization.curriculum = curriculum
        topics.append(optimization)

        // Topic 7: Save and Load the Model
        let saveLoad = Topic(context: context)
        saveLoad.id = UUID()
        saveLoad.title = "Save and Load the Model"
        saveLoad.outline = """
            In this section we will look at how to persist model state with saving, loading \
            and running model predictions. PyTorch models store the learned parameters in an \
            internal state dictionary, called state_dict. These can be persisted via \
            torch.save and loaded with torch.load.
            """
        saveLoad.objectives = [
            "Understand the state_dict and its role in model persistence",
            "Save model weights using torch.save()",
            "Load model weights using torch.load() and load_state_dict()",
            "Save and load complete models vs just state dictionaries",
            "Run inference with a loaded model"
        ]
        saveLoad.mastery = 0
        saveLoad.curriculum = curriculum
        topics.append(saveLoad)

        // Topic 8: Putting It All Together
        let integration = Topic(context: context)
        integration.id = UUID()
        integration.title = "Complete Training Pipeline"
        integration.outline = """
            This final module brings together everything learned to create a complete \
            machine learning pipeline: loading data, building a model, training with \
            optimization, evaluating performance, and saving the trained model for later use.
            """
        integration.objectives = [
            "Structure a complete PyTorch training script",
            "Implement data loading with appropriate transforms",
            "Define and instantiate a neural network architecture",
            "Set up loss function and optimizer",
            "Run the training loop for multiple epochs",
            "Evaluate model performance on test data",
            "Save the trained model for deployment"
        ]
        integration.mastery = 0
        integration.curriculum = curriculum
        topics.append(integration)

        return topics
    }

    /// Delete all sample curriculum data
    @MainActor
    public func deleteSampleCurriculum() throws {
        let context = persistenceController.viewContext

        let request = Curriculum.fetchRequest()
        request.predicate = NSPredicate(format: "name == %@", "PyTorch Fundamentals")

        let results = try context.fetch(request)
        for curriculum in results {
            context.delete(curriculum)
        }

        try persistenceController.save()
    }

    /// Delete ALL curricula (not just sample)
    @MainActor
    public func deleteAllCurricula() throws {
        let context = persistenceController.viewContext

        let request = Curriculum.fetchRequest()
        let results = try context.fetch(request)

        for curriculum in results {
            context.delete(curriculum)
        }

        try persistenceController.save()
    }
}
