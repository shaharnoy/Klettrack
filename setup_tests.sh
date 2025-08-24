#!/bin/bash

# Setup script to properly configure test target for ClimbingProgram
echo "🔧 Setting up test target for ClimbingProgram..."

# Navigate to project directory
cd "$(dirname "$0")"

# Create proper test scheme
echo "📋 Creating test scheme..."
mkdir -p ClimbingProgram.xcodeproj/xcshareddata/xcschemes

cat > ClimbingProgram.xcodeproj/xcshareddata/xcschemes/ClimbingProgramTests.xcscheme << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1640"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "NO"
            buildForArchiving = "NO"
            buildForAnalyzing = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "53229DCD2E573C2200D1A229"
               BuildableName = "ClimbingProgram.app"
               BlueprintName = "ClimbingProgram"
               ReferencedContainer = "container:ClimbingProgram.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <TestPlans>
      </TestPlans>
      <Testables>
         <TestableReference
            skipped = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "ClimbingProgramTests"
               BuildableName = "ClimbingProgramTests.xctest"
               BlueprintName = "ClimbingProgramTests"
               ReferencedContainer = "container:ClimbingProgram.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "53229DCD2E573C2200D1A229"
            BuildableName = "ClimbingProgram.app"
            BlueprintName = "ClimbingProgram"
            ReferencedContainer = "container:ClimbingProgram.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
</Scheme>
EOF

echo "✅ Test setup complete!"
echo ""
echo "📝 Next steps:"
echo "1. Open ClimbingProgram.xcodeproj in Xcode"
echo "2. Go to File > New > Target..."
echo "3. Choose 'Unit Testing Bundle'"
echo "4. Name it 'ClimbingProgramTests'"
echo "5. Make sure target to be tested is 'ClimbingProgram'"
echo "6. Delete the default test file and add your existing test files"
echo ""
echo "After that, CMD+U will work to run tests!"