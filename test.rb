class ClassName
  warning = <<~HTML
    <body>
      Hello world
    </body>
  HTML

  warning = <<~STRING
    You're deploying to protected namespace #{@namespace}, which cannot be pruned.
    Existing resources can only be removed manually. Removing templates from the set deployed will have no effect.
    ***Please do not deploy to #{@namespace} unless you really know what you are doing.**
  STRING
end
