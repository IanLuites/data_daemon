%{
  checks: [
    # {Tidy.Checks.DescribeOptions, [level: :warning, args: [:opts, :options]]},
    # {Tidy.Checks.FunctionArgumentDocumentation,
    #  [level: :warning, exceptions: ["opts", "options"]]},
    {Tidy.Checks.FunctionDoc, [level: :error]},
    # {Tidy.Checks.FunctionExamples, [level: :suggest]},
    {Tidy.Checks.FunctionSpec, [level: :error]},
    {Tidy.Checks.ImplementationMentionBehavior, [level: :warning, args: [:opts, :options]]},
    {Tidy.Checks.ModuleDoc, [level: :error]}
  ],
  ignore: %{
    functions: [
      __struct__: 0,
      __struct__: 1,
      __changeset__: 0,
      __schema__: 1,
      __schema__: 2,
      child_spec: 0,
      child_spec: 1,
      code_change: 3,
      handle_call: 3,
      handle_cast: 2,
      terminate: 2
    ],
    modules: [
      DataDaemon.Hound
    ]
  }
}
