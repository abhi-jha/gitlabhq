module Clusters
  class Cluster < ActiveRecord::Base
    include Presentable

    self.table_name = 'clusters'

    APPLICATIONS = {
      Applications::Helm.application_name => Applications::Helm,
      Applications::Ingress.application_name => Applications::Ingress,
      Applications::Prometheus.application_name => Applications::Prometheus
    }.freeze

    belongs_to :user

    has_many :cluster_projects, class_name: 'Clusters::Project'
    has_many :projects, through: :cluster_projects, class_name: '::Project'

    # we force autosave to happen when we save `Cluster` model
    has_one :provider_gcp, class_name: 'Clusters::Providers::Gcp', autosave: true

    has_one :platform_kubernetes, class_name: 'Clusters::Platforms::Kubernetes', autosave: true

    has_one :application_helm, class_name: 'Clusters::Applications::Helm'
    has_one :application_ingress, class_name: 'Clusters::Applications::Ingress'
    has_one :application_prometheus, class_name: 'Clusters::Applications::Prometheus'

    accepts_nested_attributes_for :provider_gcp, update_only: true
    accepts_nested_attributes_for :platform_kubernetes, update_only: true

    validates :name, cluster_name: true
    validate :restrict_modification, on: :update

    delegate :status, to: :provider, allow_nil: true
    delegate :status_reason, to: :provider, allow_nil: true
    delegate :on_creation?, to: :provider, allow_nil: true

    delegate :active?, to: :platform_kubernetes, prefix: true, allow_nil: true
    delegate :installed?, to: :application_helm, prefix: true, allow_nil: true

    enum platform_type: {
      kubernetes: 1
    }

    enum provider_type: {
      user: 0,
      gcp: 1
    }

    scope :enabled, -> { where(enabled: true) }
    scope :disabled, -> { where(enabled: false) }

    scope :for_environment, -> (env) { where(environment_scope: ['*', '', env.slug]) }
    scope :for_all_environments, -> { where(environment_scope: ['*', '']) }

    def status_name
      if provider
        provider.status_name
      else
        :created
      end
    end

    def created?
      status_name == :created
    end

    def applications
      [
        application_helm || build_application_helm,
        application_ingress || build_application_ingress,
        application_prometheus || build_application_prometheus
      ]
    end

    def provider
      return provider_gcp if gcp?
    end

    def platform
      return platform_kubernetes if kubernetes?
    end

    def managed?
      !user?
    end

    def first_project
      return @first_project if defined?(@first_project)

      @first_project = projects.first
    end
    alias_method :project, :first_project

    def kubeclient
      platform_kubernetes.kubeclient if kubernetes?
    end

    private

    def restrict_modification
      if provider&.on_creation?
        errors.add(:base, "cannot modify during creation")
        return false
      end

      true
    end
  end
end
