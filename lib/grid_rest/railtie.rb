module GridRest
  class Railtie < Rails::Railtie
    #rake_tasks do
    #  load "tasks/tiny_mce.rake"
    #end

    initializer :grid_rest do
      GridRest.load_config!
    end
  end
end
