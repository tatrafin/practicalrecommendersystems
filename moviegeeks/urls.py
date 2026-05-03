from django.urls import path

from moviegeeks import views

urlpatterns = [
    path('', views.index, name='index'),
    path('movie/<int:movie_id>/', views.detail, name='detail'),
    path('genre/<slug:genre_id>/', views.genre, name='genre'),
    path('search/', views.search_for_movie, name='search_for_movie'),
]
