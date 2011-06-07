module GridRest
  class Railtie < Rails::Railtie
    #rake_tasks do
    #  load "tasks/tiny_mce.rake"
    #end

    initializer :grid_rest do |app|
      app.config.after_initialize do
        GridRest.load_config!
      end
    end
  end
end
