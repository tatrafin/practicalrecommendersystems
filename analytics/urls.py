from django.urls import path
from analytics import views

urlpatterns = [
    path('', views.index, name='index'),
    path('user/<int:user_id>/', views.user, name='user'),
    path('content/<int:content_id>/', views.content, name='content'),
    path('cluster/<int:cluster_id>/', views.cluster, name='cluster'),
    path('api/get_statistics', views.get_statistics, name='get statistics'),
    path('api/events_on_conversions', views.events_on_conversions, name='events_on_conversions'),
    path('api/ratings_distribution', views.ratings_distribution, name='ratings_distribution'),
    path('api/top_content', views.top_content, name='top_content'),
    path('api/clusters', views.clusters, name='clusters'),
    path('lda', views.lda, name='lda'),
    path('similarity', views.similarity_graph, name='similarity_graph'),
]
