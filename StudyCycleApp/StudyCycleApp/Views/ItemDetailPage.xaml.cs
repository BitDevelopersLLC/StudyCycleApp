using StudyCycleApp.ViewModels;
using System.ComponentModel;
using Xamarin.Forms;

namespace StudyCycleApp.Views
{
    public partial class ItemDetailPage : ContentPage
    {
        public ItemDetailPage()
        {
            InitializeComponent();
            BindingContext = new ItemDetailViewModel();
        }
    }
}